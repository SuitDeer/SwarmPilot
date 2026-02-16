# SwarmPilot

<p align="center">
  <img src="pictures/spaceship.svg" alt="cargo spaceship" width="300">
</p>

<p align="center"><b>Deploy your Swarm cluster with one script — automatically
</b></p>

SwarmPilot helps you to deploy a high available docker swarm cluster from 1 to 9 nodes with the following components:

## Components

### Automated [Docker](https://www.docker.com) Installation
- Installs Docker Engine, Docker CLI, containerd.io, and Docker plugins on all nodes
- Configures Docker service to start automatically on boot
- Validates Docker installation with hello-world test

### [Docker Swarm](https://docs.docker.com/engine/swarm/) Setup
- Initializes Docker Swarm on the local node
- Joins remote nodes to the swarm cluster
- Supports clusters from 1 to 10 nodes

### High Availability with [Keepalived](https://keepalived.org/)
- Configures keepalived for virtual IP management
- Automatic failover between nodes
- Priority-based master election (local node gets highest priority)
- Unicast peer configuration for communication

### File Synchronization with [Syncthing4Swarm](https://github.com/SuitDeer/syncthing4swarm/tree/main)
- Deploys Syncthing4Swarm service across all nodes
- Ensures persistent volume synchronization
- Health checks to verify synchronization status

### Docker Management with [Portainer](https://www.portainer.io/)
- Installs Portainer CE LTS
- Configures Portainer Agent for swarm integration
- Exposes Portainer on ports 9443 (HTTPS) and 8000 (HTTP)
- Data persistence via Syncthing4Swarm

### Reverse Proxy with [Nginx Proxy Manager](https://nginxproxymanager.com/)
- Installs Nginx Proxy Manager for reverse proxy and SSL termination
- Exposes on ports 80 (HTTP), 81 (Web UI), and 443 (HTTPS)
- Data persistence via Syncthing4Swarm
- Configured for cluster-wide access

## Topology

![topology](pictures/topology.svg)

## Requirements

- Ubuntu Server installed on all nodes
- SSH access on all nodes
- Root access on all nodes
- Additional unused IP address for keepalived (virtual IP of the docker swarm cluster)
- `sshpass` must be installed on all nodes: `sudo apt install sshpass`

## Quick Start

Run only on **one node**:

```bash
# Clone the repository
git clone https://github.com/SuitDeer/SwarmPilot.git
cd SwarmPilot

# Deploy to Swarm
sudo chmod +x swarmpilot.sh
sudo ./swarmpilot.sh
```

---
---

## Script Workflow

The [`swarmpilot.sh`](swarmpilot.sh) script automates the entire cluster setup process through the following steps:

### Step 1: User Input Collection
- **Local Node IP**: The IP address of the node running the script
- **Node Count**: Number of nodes in the cluster (1-9, including the local node)
- **Remote Node Information**: For each remote node, the script collects:
  - IP address
  - Username
  - Password (validated for length 8-128 characters)

### Step 2: Pre-flight Checks
- Verifies `sshpass` is installed on the local node
- Checks `sshpass` installation on all remote nodes
- Ensures SSH connectivity to all nodes

### Step 3: Docker Installation on Local Node
- Updates package lists
- Installs required dependencies (ca-certificates, curl)
- Adds Docker GPG key and repository
- Installs Docker Engine, CLI, containerd.io, and Docker plugins
- Enables and starts Docker service
- Validates installation with hello-world test

### Step 4: Docker Installation on Remote Nodes
- Executes the same Docker installation commands on all remote nodes
- Validates installation on each node

### Step 5: Docker Swarm Initialization
- Initializes Docker Swarm on the local node with the specified advertise address
- Retrieves the manager join token
- Joins all remote nodes to the swarm using the join token

### Step 6: Keepalived Configuration (for clusters > 1 node)
- Prompts for virtual IP address for the cluster
- Calculates priorities for each node (local node: 255, remote nodes: 254, 253, etc.)
- Installs and configures keepalived on all nodes:
  - Detects network interface automatically
  - Creates keepalived configuration with unicast peers
  - Sets state (MASTER for local node, BACKUP for remote nodes)
  - Enables and starts keepalived service
- Configures automatic failover between nodes

### Step 7: Syncthing4Swarm Installation
- Creates `/var/syncthing/data` directory on all nodes
- Clones the Syncthing4Swarm repository on the local node
- Deploys Syncthing4Swarm Docker stack
- Installs Syncthing4Swarm on all remote nodes
- Monitors container health until all containers are healthy

### Step 8: Portainer Installation
- Creates portainer data directory
- Creates portainer.yaml configuration file with:
  - Portainer Agent (global deployment)
  - Portainer CE LTS (replicated deployment on manager nodes)
  - Network configuration (overlay driver)
  - Volume mounts for data persistence
- Deploys Portainer stack
- Exposes Portainer on ports 9443 (HTTPS) and 8000 (HTTP)
- Verifies Portainer accessibility

### Step 9: Nginx Proxy Manager Installation
- Creates data directories for Nginx Proxy Manager
- Creates nginxproxymanager.yaml configuration file with:
  - Nginx Proxy Manager application
  - Volume mounts for data persistence
  - Network configuration (overlay driver)
- Deploys Nginx Proxy Manager stack
- Exposes on ports 80 (HTTP), 81 (Web UI), and 443 (HTTPS)
- Verifies Nginx Proxy Manager accessibility
