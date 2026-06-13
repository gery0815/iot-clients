# Node-RED + openCCU Docker Setup

This project provides a Docker Compose setup for running:

- **Node-RED**
- **openCCU**

It also includes an `install.sh` script that can:

1. download or clone the project files,
2. enter the project directory,
3. start the containers with Docker Compose.

## Requirements

Before using the installer, make sure the following tools are installed:

- [Git](https://git-scm.com/)
- [Docker](https://www.docker.com/)
- Docker Compose plugin (`docker compose`) or legacy `docker-compose`
- optionally `curl` or `wget` for direct script download

## Files

- `docker-compose.yml` — defines the Node-RED and openCCU containers
- `install.sh` — clones the repository and starts the containers

## Download and install

### Option 1: Download only the install script with curl

```bash
curl -O https://raw.githubusercontent.com/gery0815/iot-clients/main/install.sh
chmod +x install.sh
./install.sh https://github.com/gery0815/iot-clients.git
```

### Option 2: Download only the install script with wget

```bash
wget https://raw.githubusercontent.com/gery0815/iot-clients/main/install.sh
chmod +x install.sh
./install.sh https://github.com/gery0815/iot-clients.git
```

### Option 3: Clone the full repository

```bash
git clone https://github.com/gery0815/iot-clients.git
cd iot-clients
chmod +x install.sh
./install.sh https://github.com/gery0815/iot-clients.git
```

## What the script does

The script will:

1. check whether a Git repository URL was provided,
2. clone the repository if the project directory does not already exist,
3. change into the project directory,
4. detect whether `docker compose` or `docker-compose` is available,
5. start the containers in the background.

## If Docker permission is denied

If you see an error like:

```bash
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

you can either:

### Option 1: use sudo

```bash
sudo ./install.sh https://github.com/gery0815/iot-clients.git
```

### Option 2: add your user to the docker group

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

Then try again:

```bash
./install.sh https://github.com/gery0815/iot-clients.git
```

## Start containers manually

If the repository is already cloned, you can start the containers manually:

```bash
docker compose up -d
```

or:

```bash
docker-compose up -d
```

## Stop containers

```bash
docker compose down
```

or:

```bash
docker-compose down
```

## Access the services

After startup, the services are available at:

- **Node-RED:** `http://localhost:1880`
- **openCCU:** `http://localhost`

## Notes

- Port `80` is used by openCCU and may conflict with another web server already running on the host.
- openCCU may require additional configuration depending on your hardware and environment.
- If Docker requires elevated permissions, the script may retry with `sudo`.

## Troubleshooting

### Docker Compose not found

If you get:

```bash
Docker Compose not found. Please install Docker and Docker Compose first.
```

install Docker and the Compose plugin, then rerun the script.

### Containers do not start

Check container logs with:

```bash
docker compose logs
```

or:

```bash
docker-compose logs
```

### Check running containers

```bash
docker ps
```