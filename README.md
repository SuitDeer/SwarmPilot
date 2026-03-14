# SwarmPilot 

> ℹ️ For all that are currently using the `suitdeer/syncthing4swarm`-docker image, please switch to `syncthing4swarm/syncthing4swarm`-docker image. (My pull request repository was merged into the main repository 😄)
>
> 1. Update the `syncthing4swarm.yaml` file inside the `SwarmPilot` folder. 
> 
>    Replace the the line `image: suitdeer/syncthing4swarm:latest` 
> 
>    with `image: syncthing4swarm/syncthing4swarm:latest`
> 2. Update the syncthing4swarm docker service:
> 
>    ```bash
>    cd SwarmPilot
>    sudo docker stack deploy --resolve-image=always -c syncthing4swarm.yaml syncthing4swarm
>    ```

> For all that are new (after 07.03.2026) you do not need to do anything 😄

<p align="center">
  <img src="pictures/spaceship.svg" alt="cargo spaceship" width="300">
</p>

<p align="center"><b>Deploy your Swarm cluster with one script — automatically
</b></p>

SwarmPilot helps you to deploy a high available docker swarm cluster from 1 to 9 nodes with the following components:

## Components

### [Docker](https://www.docker.com)
Docker is a technology that bundles a software program with all the other software that application needs to run, such as an operating system, third-party software libraries, etc. Software bundled like this is called a container.

### [Keepalived](https://keepalived.org/)
Used for managing a virtual IP address for all cluster nodes

### [Syncthing4Swarm](https://github.com/SuitDeer/syncthing4swarm/tree/main)
Ensures persistent volume synchronization

### [Portainer](https://www.portainer.io/)
It provides an intuitive graphical user interface and extensive API for managing resources such as containers, images, and networks via a 

Web interface: [https://<virtual_ip>:9443](https://<virtual_ip>:9443)

### [Nginx Proxy Manager](https://nginxproxymanager.com/) or [Traefik](https://traefik.io/traefik)
Used for a central reverse proxy and SSL termination for other docker services on this cluster. 

#### Nginx Proxy Manager
Web Interface: [http://<virtual_ip>:81](http://<virtual_ip>:81)

#### Traefik
Web Interface: [https://<virtual_ip>/dashboard/](https://<virtual_ip>/dashboard/)
Dashboard authentication: Basic Auth (username and password are requested during installation)

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

## Setup Video

<!-- Embedding a GitHub Release video with HTML5 -->
<video controls>
  <source src="https://raw.githubusercontent.com/SuitDeer/SwarmPilot/refs/heads/main/pictures/setup-demo-video.mp4" type="video/mp4">
  Your browser does not support the video tag.  
</video>

https://github.com/user-attachments/assets/4bd35877-4b11-4a83-b456-ab66db2a5267

## Setup a demo service with lets encrypt certificate on cluster

Please use the `reverse_proxy` overlay network for your stacks if you need ssl termination via Nginx Proxy Manager or Traefik.


Example:

If your stack containers need persistent volumes please first create the root directory in the syced syncthind directory:

```bash
sudo mkdir /var/syncthing/data/<FOLDER_NAME>
```

### Nginx Proxy Manager

<details>
<summary>Instructions for setting up a Service with Nginx Proxy Manager</summary>

```yaml
services:
  webserver:
    image: nginxdemos/hello
    volumes:
     - /var/syncthing/data/<FOLDER_NAME>:/var/www/html
    networks:
      - reverse_proxy
    ports:
      - 8082:80
networks:
  reverse_proxy:
    external: true
```

Since both the Nginx Proxy Manager container and your new service stack are connected to the same overlay network `reverse_proxy`, you should reference containers in Nginx Proxy Manager by their service names.

```
services:
  webserver: <---- This is the service-name of the container
...............
```

![Nginy Proxy Manager adding a Proxy Host](pictures/nginx-proxy-manager.png)

</details>


### Traefik

<details>
<summary>Instructions for setting up a Service with Traefik</summary>

**Please edit `app.example.com` to your liking**

```yaml
services:
  webserver:
    image: nginxdemos/hello
    volumes:
     - /var/syncthing/data/<FOLDER_NAME>:/var/www/html
    networks:
      - reverse_proxy
    ports:
      - 8082:80
    deploy:
      labels:
        # Enable Traefik routing for this service
        - traefik.enable=true

        # Define the router
        - traefik.http.routers.webapp.rule=Host(`app.example.com`)
        - traefik.http.routers.webapp.entrypoints=websecure
        - traefik.http.routers.webapp.tls.certresolver=letsencrypt

        # Define the service (required for Swarm)
        - traefik.http.services.webapp.loadbalancer.server.port=8082

        # Health check for load balancing
        - traefik.http.services.webapp.loadbalancer.healthcheck.path=/
        - traefik.http.services.webapp.loadbalancer.healthcheck.interval=10s
networks:
  reverse_proxy:
    external: true
```

</details>

## Maintanance

### Upgrade Syncthing4Swarm Stack

```bash
cd SwarmPilot
sudo docker stack deploy --resolve-image=always -c syncthing4swarm.yaml syncthing4swarm
```

### Upgrade Portainer Stack

```bash
cd SwarmPilot
sudo docker stack deploy --resolve-image=always -c portainer.yaml portainer
```

### Upgrade Nginx Proxy Manager Stack

```bash
cd SwarmPilot
sudo docker stack deploy --resolve-image=always -c nginxproxymanager.yaml nginxproxymanager
```

### Upgrade Traefik Stack

```bash
cd SwarmPilot
sudo docker stack deploy --resolve-image=always -c traefik.yaml traefik
```

---
---

## Detailed Script Workflow Steps

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

### Step 3: Docker Installation
- Updates package lists
- Installs required dependencies (ca-certificates, curl)
- Adds Docker GPG key and repository
- Installs Docker Engine, CLI, containerd.io, and Docker plugins
- Enables and starts Docker service
- Validates installation with hello-world test

### Step 4: Docker Swarm Initialization
- Initializes Docker Swarm on the local node with the specified advertise address
- Retrieves the manager join token
- Joins all remote nodes to the swarm using the join token

### Step 5: Keepalived Configuration (for clusters > 1 node)
- Prompts for virtual IP address for the cluster
- Calculates priorities for each node (local node: 255, remote nodes: 254, 253, etc.)
- Installs and configures keepalived on all nodes:
  - Detects network interface automatically
  - Creates keepalived configuration with unicast peers
  - Sets state (MASTER for local node, BACKUP for remote nodes)
  - Enables and starts keepalived service
- Configures automatic failover between nodes

### Step 6: Syncthing4Swarm Installation
- For clusters with more than 1 node: creates `/var/syncthing/data` on all nodes
- On the local node: creates `syncthing4swarm.yaml` and deploys the Syncthing4Swarm stack
- On remote nodes: prepares the required syncthing directory
- For single-node clusters: skips Syncthing4Swarm setup

### Step 7: Portainer Installation
- Waits until Syncthing4Swarm containers report healthy on all nodes
- Creates portainer data directory
- Creates portainer.yaml configuration file
- Deploys Portainer stack
- Exposes Portainer on ports 9443 (HTTPS) and 8000 (HTTP)
- Publishes the Portainer dashboard at `https://<virtual_ip>:9443`

### Step 8: Reverse Proxy Selection and Installation

- Prompts the user to choose `Traefik` or `Nginx Proxy Manager`
- If `Traefik` is selected, the script:
  - Prompts for a valid email address for Let's Encrypt ACME
  - Prompts for dashboard username and password
  - Generates a password hash for Traefik Basic Auth
  - Creates the shared overlay network `reverse_proxy` (if needed)
  - Creates `traefik.yaml` and deploys the Traefik stack
  - Exposes ports 80 (HTTP) and 443 (HTTPS)
  - Publishes the Traefik dashboard at `https://<virtual_ip>/dashboard/` (protected by Basic Auth)
- If `Nginx Proxy Manager` is selected, the script:
  - Creates required Nginx Proxy Manager data directories
  - Creates the shared overlay network `reverse_proxy` (if needed)
  - Creates `nginxproxymanager.yaml` and deploys the Nginx Proxy Manager stack
  - Exposes ports 80 (HTTP), 81 (Web UI), and 443 (HTTPS)
  - Publishes the Nginx Proxy Manager dashboard at `http://<virtual_ip>:81`
