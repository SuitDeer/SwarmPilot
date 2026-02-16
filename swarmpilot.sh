#!/bin/bash

# SwarmPilot - Docker Cluster Setup Script
# This script installs Docker Engine on Ubuntu server nodes

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display banner
display_banner() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║           SwarmPilot - Docker Cluster Setup                ║"
    echo "║                                                            ║"
    echo "║         Automated Docker Installation for Ubuntu           ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Function to get user input with validation
get_valid_input() {
    local prompt="$1"
    local validator="$2"

    while true; do
        read -p "$prompt"
        if eval "$validator"; then
            echo "$REPLY"
            return
        fi
    done
}

# Function to validate node count
validate_node_count() {
    local count="$1"
    [[ "$count" =~ ^[1-9]$ ]] && [[ "$count" -lt 10 ]]
}

# Function to validate IP address
validate_ip() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && 
    [[ $(echo "$ip" | cut -d. -f1) -le 255 ]] && 
    [[ $(echo "$ip" | cut -d. -f2) -le 255 ]] && 
    [[ $(echo "$ip" | cut -d. -f3) -le 255 ]] && 
    [[ $(echo "$ip" | cut -d. -f4) -le 255 ]]
}

# Function to validate username
validate_username() {
    local username="$1"
    [[ "$username" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] && [[ ${#username} -ge 3 ]] && [[ ${#username} -le 32 ]]
}

# Function to validate password
validate_password() {
    local password="$1"
    [[ ${#password} -ge 8 ]] && [[ ${#password} -le 128 ]]
}

# Function to get password with masking
get_password() {
    local prompt="$1"
    local password
    read -r -s -p "$prompt" password
    echo >&2
    printf '%s\n' "$password"
}

# Function to execute command on remote node with sudo (non-interactive)
remote_exec_sudo() {
    local node_ip="$1"
    local username="$2"
    local password="$3"
    local command="$4"
    local quoted_command

    printf -v quoted_command '%q' "$command"
    printf '%s\n' "$password" | sshpass -p "$password" ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$username@$node_ip" "sudo -S -p '' bash -lc $quoted_command"
}

# Function to execute remote sudo command with additional stdin payload
remote_exec_sudo_with_stdin() {
    local node_ip="$1"
    local username="$2"
    local password="$3"
    local command="$4"
    local stdin_payload="$5"
    local quoted_command

    printf -v quoted_command '%q' "$command"
    {
        printf '%s\n' "$password"
        printf '%s' "$stdin_payload"
    } | sshpass -p "$password" ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$username@$node_ip" "sudo -S -p '' bash -lc $quoted_command"
}

# Function to detect network interface
detect_network_interface() {
    local is_local="${1:-false}"
    local node_ip="$2"
    local username="$3"
    local password="$4"

    if [ "$is_local" = true ]; then
        # Detect interface on local node
        local interface_name=$(ip -br addr show | grep "$node_ip" | awk '{print $1}')
        if [ -z "$interface_name" ]; then
            log_error "Could not detect network interface on local node"
            return 1
        fi
        echo "$interface_name"
    else
        # Detect interface on remote node
        local interface_name
        interface_name=$(remote_exec_sudo "$node_ip" "$username" "$password" "ip -br addr show | grep '$node_ip' | awk '{print \$1}'")
        if [ -z "$interface_name" ]; then
            log_error "Could not detect network interface on node $node_ip"
            return 1
        fi
        echo "$interface_name"
    fi
}

# Function to install and configure keepalived
install_keepalived() {
    local node_ip="$1"
    local username="$2"
    local password="$3"
    local node_name="$4"
    local is_local="${5:-false}"
    local virtual_ip="$6"
    local priority="$7"
    local unicast_peers="$8"

    if [ "$is_local" = true ]; then
        log_info "Installing and configuring keepalived on local node..."
    else
        log_info "Installing and configuring keepalived on node $node_name..."
    fi

    # Install keepalived
    local install_cmd="sudo apt -q=3 update && sudo apt install -y -q=3 keepalived"
    if [ "$is_local" = true ]; then
        if ! eval "$install_cmd"; then
            log_error "Failed to install keepalived on local node"
            return 1
        fi
    else
        if ! remote_exec_sudo "$node_ip" "$username" "$password" "$install_cmd"; then
            log_error "Failed to install keepalived on node $node_name"
            return 1
        fi
    fi

    # Detect network interface
    local interface
    interface=$(detect_network_interface "$is_local" "$node_ip" "$username" "$password")
    if [ -z "$interface" ]; then
        return 1
    fi

    # Create keepalived configuration
    local state="MASTER"
    if [ "$is_local" = false ]; then
        state="BACKUP"
    fi

    local config_content="vrrp_instance VI_1 {
        state $state
        interface $interface
        virtual_router_id 51
        priority $priority
        advert_int 1
        authentication {
              auth_type PASS
              auth_pass 12345
        }
        unicast_peer {
"
    # Add unicast peers
    IFS=' ' read -ra PEERS <<< "$unicast_peers"
    for peer in "${PEERS[@]}"; do
        config_content+="            $peer
"
    done
    config_content+="        }
        virtual_ipaddress {
              $virtual_ip/24
        }
}"

    # Write configuration
    if [ "$is_local" = true ]; then
        if ! echo "$config_content" | sudo tee /etc/keepalived/keepalived.conf > /dev/null; then
            log_error "Failed to write keepalived configuration on local node"
            return 1
        fi
    else
        if ! remote_exec_sudo_with_stdin "$node_ip" "$username" "$password" "tee /etc/keepalived/keepalived.conf > /dev/null" "$config_content"; then
            log_error "Failed to write keepalived configuration on node $node_name"
            return 1
        fi
    fi

    # Enable and start keepalived
    local enable_cmd="sudo systemctl enable keepalived && sudo systemctl start keepalived"
    if [ "$is_local" = true ]; then
        if ! eval "$enable_cmd"; then
            log_error "Failed to enable keepalived on local node"
            return 1
        fi
    else
        if ! remote_exec_sudo "$node_ip" "$username" "$password" "$enable_cmd"; then
            log_error "Failed to enable keepalived on node $node_name"
            return 1
        fi
    fi

    if [ "$is_local" = true ]; then
        log_success "Keepalived successfully installed and configured on local node"
    else
        log_success "Keepalived successfully installed and configured on node $node_name"
    fi
    return 0
}

# Function to install syncthing4swarm on all nodes
install_syncthing4swarm() {
    local node_ip="$1"
    local username="$2"
    local password="$3"
    local node_name="$4"
    local is_local="${5:-false}"

    if [ "$is_local" = true ]; then
        log_info "Installing syncthing4swarm on local node..."
    else
        log_info "Installing syncthing4swarm on node $node_name..."
    fi

    # Create /var/syncthing/data directory on all nodes
    local create_dir_cmd="sudo mkdir -p /var/syncthing/data"
    if [ "$is_local" = true ]; then
        if ! eval "$create_dir_cmd"; then
            log_error "Failed to create /var/syncthing/data on local node"
            return 1
        fi
    else
        if ! remote_exec_sudo "$node_ip" "$username" "$password" "$create_dir_cmd"; then
            log_error "Failed to create /var/syncthing/data on node $node_name"
            return 1
        fi
    fi

    # On local node only: clone repository and deploy docker stack
    if [ "$is_local" = true ]; then
        log_info "Cloning syncthing4swarm repository..."

        # Check if directory already exists
        if [ -d "syncthing4swarm" ]; then
            log_warning "syncthing4swarm directory already exists. Skipping clone."
        else
            if ! git clone https://github.com/SuitDeer/syncthing4swarm.git; then
                log_error "Failed to clone syncthing4swarm repository"
                return 1
            fi
        fi

        cd syncthing4swarm

        log_info "Deploying syncthing4swarm with Docker Stack..."
        if ! sudo docker stack deploy -c docker-compose.yml syncthing4swarm; then
            log_error "Failed to deploy syncthing4swarm stack"
            cd ..
            return 1
        fi

        cd ..

        log_success "syncthing4swarm successfully deployed on local node"
    else
        log_success "syncthing4swarm directory created on node $node_name"
    fi

    return 0
}

# Function to check syncthing container health on all nodes
check_syncthing_health() {
    local node_ip="$1"
    local username="$2"
    local password="$3"
    local node_name="$4"
    local is_local="${5:-false}"

    if [ "$is_local" = true ]; then
        log_info "Checking syncthing container health on local node..."
    else
        log_info "Checking syncthing container health on node $node_name..."
    fi

    local check_cmd="sudo docker ps --filter 'name=syncthing4swarm_syncthing4swarm' --format '{{.Status}}'"
    local container_status

    if [ "$is_local" = true ]; then
        container_status=$(eval "$check_cmd")
    else
        container_status=$(remote_exec_sudo "$node_ip" "$username" "$password" "$check_cmd")
    fi

    if [ -z "$container_status" ]; then
        log_error "No syncthing containers found on $node_name"
        return 1
    fi

    # Check if all containers are healthy
    if echo "$container_status" | grep -q "healthy"; then
        if [ "$is_local" = true ]; then
            log_success "syncthing containers are healthy on local node"
        else
            log_success "syncthing containers are healthy on node $node_name"
        fi
        return 0
    else
        log_error "syncthing containers are not healthy on $node_name. Status: $container_status"
        return 1
    fi
}

# Function to install portainer on local node
install_portainer() {
    log_info "Installing Portainer on local node..."

    # Create portainer data directory
    if ! sudo mkdir -p /var/syncthing/data/portainer; then
        log_error "Failed to create portainer data directory"
        return 1
    fi

    # Create portainer.yaml configuration file
    log_info "Creating portainer configuration file..."
    if ! bash -c 'cat <<EOF > ~/portainer.yaml
services:
  agent:
    image: portainer/agent:lts
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - agent_network
    deploy:
      restart_policy:
        condition: any
        delay: 5s
        max_attempts: 3
        window: 120s
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  portainer:
    image: portainer/portainer-ce:lts
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    ports:
      - "9443:9443"
      - "8000:8000"
    volumes:
      - /var/syncthing/data/portainer:/data
    networks:
      - agent_network
    deploy:
      restart_policy:
        condition: any
        delay: 60s
        max_attempts: 3
        window: 180s
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
networks:
  agent_network:
    driver: overlay
    attachable: true
EOF'; then
        log_error "Failed to create portainer configuration file"
        return 1
    fi

    # Deploy portainer stack
    log_info "Deploying Portainer stack..."
    if ! sudo docker stack deploy portainer -c portainer.yaml; then
        log_error "Failed to deploy portainer stack"
        return 1
    fi

    log_success "Portainer successfully deployed on local node"
    log_info "Portainer will be accessible at https://<virtual_ip>:9443"
    return 0
}

# Function to install Docker on a node (local or remote)
install_docker() {
    local node_ip="$1"
    local username="$2"
    local password="$3"
    local node_name="$4"
    local is_local="${5:-false}"

    if [ "$is_local" = true ]; then
        log_info "Installing Docker on local node..."
    else
        log_info "Installing Docker on node $node_name..."
    fi

    # Docker installation commands
    local docker_commands=(
        "sudo apt -q=3 update "
        "sudo apt install -y -q=3 ca-certificates curl"
        "sudo install -m 0755 -d /etc/apt/keyrings"
        "sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc"
        "sudo chmod a+r /etc/apt/keyrings/docker.asc"
        "sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: \$(. /etc/os-release && echo "\${UBUNTU_CODENAME:-\$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF"
        "sudo apt -q=3 update"
        "sudo apt install -y -q=3 docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
        "sudo systemctl enable docker"
        "sudo systemctl start docker"
    )

    # Execute commands
    for cmd in "${docker_commands[@]}"; do
        if [ "$is_local" = true ]; then
            if ! eval "$cmd"; then
                log_error "Failed to execute command: $cmd"
                return 1
            fi
        else
            if ! remote_exec_sudo "$node_ip" "$username" "$password" "$cmd"; then
                log_error "Failed to execute command on node $node_name: $cmd"
                return 1
            fi
        fi
    done

    # Test Docker installation
    if [ "$is_local" = true ]; then
        if ! sudo docker run --rm hello-world; then
            log_warning "Docker installation may have issues"
            return 1
        fi
    else
        if ! remote_exec_sudo "$node_ip" "$username" "$password" "sudo docker run --rm hello-world"; then
            log_warning "Docker installation may have issues on node $node_name"
            return 1
        fi
    fi

    if [ "$is_local" = true ]; then
        log_success "Docker successfully installed on local node"
    else
        log_success "Docker successfully installed on node $node_name"
    fi
    return 0
}

# Main script execution
main() {
    display_banner

    ###### Step 1: Get number of nodes
    log_info "How many nodes should the cluster have? (1-9, including this node)"
    NODE_COUNT=$(get_valid_input "Enter number of nodes: " "validate_node_count \$REPLY")

    ###### Step 2: Get node information
    NODES=()
    NODE_NAMES=()

    if [ "$NODE_COUNT" -eq 1 ]; then
        log_info "Single node cluster - only local node will be configured"
        NODES=()
        NODE_NAMES=("Local Node")
    else
        log_info "Configuring $((NODE_COUNT - 1)) remote nodes (not local)..."

        for i in $(seq 1 $((NODE_COUNT - 1))); do
            echo ""
            log_info "Node $i of $((NODE_COUNT - 1))"

            # Get IP address
            NODE_IP=$(get_valid_input "Enter IP address for node $i: " "validate_ip \$REPLY")

            # Get username
            NODE_USERNAME=$(get_valid_input "Enter username for node $i: " "validate_username \$REPLY")

            # Get password
            NODE_PASSWORD=$(get_password "Enter password for node $i: ")

            # Validate password
            while ! validate_password "$NODE_PASSWORD"; do
                log_error "Password must be 8-128 characters"
                NODE_PASSWORD=$(get_password "Enter password for node $i: ")
            done

            NODES+=("$NODE_IP:$NODE_USERNAME:$NODE_PASSWORD")
            NODE_NAMES+=("Node $i ($NODE_IP)")
        done
    fi

    # Display configuration summary
    echo ""
    log_info "Configuration Summary:"
    echo "----------------------"
    echo "Total nodes: $NODE_COUNT"
    echo "Local node: Yes"
    for i in "${!NODE_NAMES[@]}"; do
        echo "Node $((i + 1)): ${NODE_NAMES[$i]}"
    done
    echo ""

    # Confirm installation
    read -p "Do you want to proceed with Docker installation? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled by user"
        exit 0
    fi

    echo ""
    log_info "Starting Docker installation..."
    echo ""

    ###### Step 3: Install Docker on local node
    if ! install_docker "localhost" "$USER" "" "Local Node" true; then
        log_error "Failed to install Docker on local node"
        exit 1
    fi

    echo ""
    log_success "Local node Docker installation completed"
    echo ""

    ###### Step 4: Install Docker on remote nodes
    for i in "${!NODES[@]}"; do
        IFS=':' read -r NODE_IP NODE_USERNAME NODE_PASSWORD <<< "${NODES[$i]}"
        NODE_NAME="${NODE_NAMES[$i]}"

        if ! install_docker "$NODE_IP" "$NODE_USERNAME" "$NODE_PASSWORD" "$NODE_NAME" false; then
            log_error "Failed to install Docker on $NODE_NAME"
            exit 1
        fi

        echo ""
    done

    ###### Step 5: Configure keepalived
    if [ "$NODE_COUNT" -gt 1 ]; then
        echo ""
        log_info "Configuring High Availability with Keepalived..."
        echo ""
        sleep 3

        # Get virtual IP address
        VIRTUAL_IP=$(get_valid_input "Enter virtual IP address for the cluster: " "validate_ip \$REPLY")

        # Calculate priorities for each node
        local priorities=()
        local unicast_peers_list=()

        # Remote nodes get progressively lower priorities
        for i in "${!NODES[@]}"; do
            local priority=$((254 - i))
            priorities+=("$priority")
            IFS=':' read -r NODE_IP NODE_USERNAME NODE_PASSWORD <<< "${NODES[$i]}"
            unicast_peers_list+=("$NODE_IP")
        done

        # Display configuration summary
        echo ""
        log_info "Keepalived Configuration Summary:"
        echo "-----------------------------------"
        echo "Virtual IP: $VIRTUAL_IP"
        echo "Virtual Router ID: 51"
        echo "Authentication: PASS (12345)"
        echo ""
        echo "Node Priorities:"
        echo "  Local Node: 255 (MASTER)"
        for i in "${!NODES[@]}"; do
            local priority=$((254 - i))
            echo "  Node $((i + 1)): $priority (BACKUP)"
        done
        echo ""

        # Confirm keepalived installation
        echo ""
        log_info "Starting keepalived installation..."
        echo ""

        # Build unicast peers list for local node (all remote nodes)
        local local_peers=""
        for i in "${!NODES[@]}"; do
            if [ -z "$local_peers" ]; then
                local_peers="${NODES[$i]}"
            else
                local_peers="$local_peers ${NODES[$i]}"
            fi
        done


        # Get local node IP address
        LOCAL_NODE_IP=$(get_valid_input "Enter local node IP address: " "validate_ip \$REPLY")


        # Install keepalived on local node
        if ! install_keepalived "$LOCAL_NODE_IP" "$USER" "" "Local Node" true "$VIRTUAL_IP" "255" "$local_peers"; then
            log_error "Failed to install keepalived on local node"
            exit 1
        fi

        echo ""
        log_success "Local node keepalived installation completed"
        echo ""

        # Install keepalived on remote nodes
        for i in "${!NODES[@]}"; do
            IFS=':' read -r NODE_IP NODE_USERNAME NODE_PASSWORD <<< "${NODES[$i]}"
            NODE_NAME="${NODE_NAMES[$i]}"
            local priority=$((254 - i))

            # Build unicast peers list (all nodes except current)
            local peers=""
            for j in "${!NODES[@]}"; do
                if [ "$j" -ne "$i" ]; then
                    IFS=':' read -r PEER_IP PEER_USERNAME PEER_PASSWORD <<< "${NODES[$j]}"
                    if [ -z "$peers" ]; then
                        peers="$PEER_IP"
                    else
                        peers="$peers $PEER_IP"
                    fi
                fi
            done

            if ! install_keepalived "$NODE_IP" "$NODE_USERNAME" "$NODE_PASSWORD" "$NODE_NAME" false "$VIRTUAL_IP" "$priority" "$peers"; then
                log_error "Failed to install keepalived on $NODE_NAME"
                exit 1
            fi

            echo ""
        done

        echo ""
        log_success "=========================================="
        log_success "Keepalived Configuration Completed!"
        log_success "=========================================="
        echo ""
        log_info "High availability is now configured."
        log_info "The virtual IP $VIRTUAL_IP will float between nodes."
        log_info "To verify keepalived status, run: sudo systemctl status keepalived"
        echo ""
    else
        echo ""
        log_info "Skipping keepalived configuration for single node cluster"
        echo ""
    fi

    ###### Step 6: Install syncthing4swarm
    echo ""
    log_info "Configuring syncthing4swarm for file synchronization..."
    echo ""
    sleep 3

    if [ "$NODE_COUNT" -gt 1 ]; then
        echo ""
        log_info "Starting syncthing4swarm installation..."
        echo ""

        # Install syncthing4swarm on local node
        if ! install_syncthing4swarm "localhost" "$USER" "" "Local Node" true; then
            log_error "Failed to install syncthing4swarm on local node"
            exit 1
        fi

        echo ""
        log_success "Local node syncthing4swarm installation completed"
        echo ""

        # Install syncthing4swarm on remote nodes
        for i in "${!NODES[@]}"; do
            IFS=':' read -r NODE_IP NODE_USERNAME NODE_PASSWORD <<< "${NODES[$i]}"
            NODE_NAME="${NODE_NAMES[$i]}"

            if ! install_syncthing4swarm "$NODE_IP" "$NODE_USERNAME" "$NODE_PASSWORD" "$NODE_NAME" false; then
                log_error "Failed to install syncthing4swarm on $NODE_NAME"
                exit 1
            fi

            echo ""
        done

        echo ""
        log_success "=========================================="
        log_success "syncthing4swarm Installation Completed!"
        log_success "=========================================="
        echo ""
        log_info "File synchronization is now configured across all nodes."
        log_info "To verify syncthing4swarm status, run: docker service ls"
        echo ""
    else
        echo ""
        log_info "Skipping syncthing configuration for single node cluster"
        echo ""
    fi

    ###### Step 7: Install Portainer
    echo ""
    log_info "Configuring Portainer for Docker management..."
    echo ""
    sleep 3
    echo ""
    log_info "Starting Portainer installation..."
    echo ""

    # Check syncthing container health on all nodes
    log_info "Checking syncthing container health on all nodes..."
    local all_healthy=false

    while true; do
        sleep 3
        local all_pass=true
        if ! check_syncthing_health "localhost" "$USER" "" "Local Node" true; then
            all_pass=false
        fi
        for i in "${!NODES[@]}"; do
            IFS=':' read -r NODE_IP NODE_USERNAME NODE_PASSWORD <<< "${NODES[$i]}"
            NODE_NAME="${NODE_NAMES[$i]}"
            if ! check_syncthing_health "$NODE_IP" "$NODE_USERNAME" "$NODE_PASSWORD" "$NODE_NAME" false; then
                all_pass=false
            fi
        done
        if [ "$all_pass" = true ]; then
            break
        fi
        echo "Not all syncthing containers are healthy yet..."
    done

    echo ""
    log_success "All syncthing containers are healthy"
    echo ""

    # Install portainer on local node
    if ! install_portainer; then
        log_error "Failed to install Portainer on local node"
        exit 1
    fi

    echo ""
    log_success "=========================================="
    log_success "Portainer Installation Completed!"
    log_success "=========================================="
    echo ""
    log_info "Portainer is now accessible at https://<virtual_ip>:9443"
    log_info "To verify Portainer status, run: docker service ls"
    echo ""

    # Final summary
    echo ""
    log_success "=========================================="
    log_success "Docker Cluster Setup Completed Successfully!"
    log_success "=========================================="
    echo ""
    log_info "All nodes have Docker installed and running."
    log_info "You can now configure Docker Swarm or other Docker services."
    echo ""
    log_info "To verify Docker installation, run: docker version"
    echo ""
}

# Run main function
main "$@"
