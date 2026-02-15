# SwarmPilot

<p align="center">
  <img src="pictures/spaceship.svg" alt="cargo spaceship" width="300">
</p>

<p align="center"><b>Deploy your Swarm cluster with one script — automatically
</b></p>

SwarmPilot helps you to deploy a high available docker swarm cluster form 1 to 10 nodes with the following features:

- [Portainer](https://www.portainer.io/) as a Web Interface for managing docker containers.
- [Nginx Proxy Manger](https://nginxproxymanager.com/) as a Reverse Proxy for the swarm.
- [Syncthing4Swarm](https://github.com/SuitDeer/syncthing4swarm/tree/main) as persistent docker volume syncing between nodes.

- [keepalived](https://keepalived.org/) for a virtual IP-Address that is shared for all nodes of the docker swarm cluster.

## Topology

![topology](pictures/topology.svg)

## Requirments

- Ubuntu Server installed on all nodes
- You need ssh access on all nodes
- Need root access on all nodes
- You need an additional unused IP-Address for keepalived (virtual IP-Address of the docker swarm cluster)

## Quick Start

Run only on **one node**:

```bash
# Clone the repository
git clone https://github.com/SuitDeer/SwarmPilot.git
cd swarmpilot

# Deploy to Swarm
sudo chmod +x swarmpilot.sh
sudo ./swarmpilot.sh
```