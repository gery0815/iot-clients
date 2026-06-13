# Node-RED + openCCU Docker Setup

This project provides a Docker Compose setup for running:

- **Node-RED**
- **openCCU**

It also includes helper scripts to install and update the setup from the repository `gery0815/iot-clients`.

## Requirements

Before using the scripts, make sure the following tools are installed:

- [Git](https://git-scm.com/)
- [Docker](https://www.docker.com/)
- Docker Compose plugin (`docker compose`) or legacy `docker-compose`
- optionally `curl` or `wget` for direct script download

## Files

- `docker-compose.yml` — defines the Node-RED and openCCU containers
- `install.sh` — clones the repository, configures the setup, and starts the containers
- `update.sh` — reloads the latest files from Git, optionally updates configuration, and restarts the containers

## Configuration

### openCCU USB device mapping

The Docker Compose setup supports mapping a USB device from the host into the openCCU container.

By default, the scripts use:

```bash
/dev/ttyUSB0
```

During installation, `install.sh` asks for the USB device path.  
During updates, `update.sh` can optionally change it.

The selected value is stored in:

```bash
.env
```

Example:

```bash
OCCU_USB_DEVICE=/dev/ttyUSB0
```

If your RF module is connected under a different path, such as `/dev/ttyACM0`, enter that value during install or update.

### Node-RED admin credentials

The scripts create a Node-RED `settings.js` file with admin login enabled.

During installation, `install.sh` asks for:

- Node-RED username
- Node-RED password

During updates, `update.sh` can optionally change these credentials.

The generated file is stored here:

```bash
nodered-data/settings.js
```

The password is stored as a bcrypt hash, not as plain text.

## Install

### Option 1: Download only the install script with curl

```bash
curl -fLo install.sh https://raw.githubusercontent.com/gery0815/iot-clients/main/install.sh
chmod +x install.sh
./install.sh
```

### Option 2: Download only the install script with wget

```bash
wget -O install.sh https://raw.githubusercontent.com/gery0815/iot-clients/main/install.sh
chmod +x install.sh
./install.sh
```

### Option 3: Clone the full repository

```bash
git clone https://github.com/gery0815/iot-clients.git
cd iot-clients
chmod +x install.sh
./install.sh
```

### What happens during install

The install script will:

1. clone the repository,
2. ask for the openCCU USB device path,
3. ask for Node-RED admin username and password,
4. generate `.env`,
5. generate `nodered-data/settings.js`,
6. start the containers.

## Update after changes

If the repository or `docker-compose.yml` was updated, you can pull the latest version and restart the setup.

### Option 1: Run from inside the repository

```bash
cd iot-clients
chmod +x update.sh
./update.sh
```

### Option 2: Download the update script directly with curl

```bash
curl -fLo update.sh https://raw.githubusercontent.com/gery0815/iot-clients/main/update.sh
chmod +x update.sh
./update.sh
```

### Option 3: Download the update script directly with wget

```bash
wget -O update.sh https://raw.githubusercontent.com/gery0815/iot-clients/main/update.sh
chmod +x update.sh
./update.sh
```

### What happens during update

The update script will:

1. pull the latest repository changes,
2. optionally change the openCCU USB device path,
3. optionally change the Node-RED admin credentials,
4. pull updated container images,
5. restart the containers.

## Manual Docker Compose usage

If the repository is already cloned, you can start the containers manually:

```bash
docker compose up -d
```

or:

```bash
docker-compose up -d
```

To stop the containers:

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
- If Docker requires elevated permissions, the scripts automatically use `sudo`.
- The install and update scripts are fixed to use the repository `https://github.com/gery0815/iot-clients.git`.

## Troubleshooting

### 404 when downloading a script

If you download a script and get an error like:

```bash
./install.sh: line 1: 404:: command not found
```

then the file was not downloaded correctly and probably contains a GitHub 404 page instead of the shell script.

Download it again with:

```bash
curl -fLo install.sh https://raw.githubusercontent.com/gery0815/iot-clients/main/install.sh
```

or:

```bash
wget -O install.sh https://raw.githubusercontent.com/gery0815/iot-clients/main/install.sh
```

### Docker permission denied

If you see an error like:

```bash
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

you can either let the script use `sudo`, or add your user to the docker group:

```bash
sudo usermod -aG docker "$USER"
newgrp docker
```

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