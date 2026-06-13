#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/gery0815/iot-clients.git"
APP_DIR="iot-clients"

if ! command -v git >/dev/null 2>&1; then
  echo "Git is not installed. Please install Git first."
  exit 1
fi

DOCKER_PREFIX=""
DOCKER_COMPOSE_CMD=""

if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
  fi
fi

if [ -z "$DOCKER_COMPOSE_CMD" ] && command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker-compose"
fi

if [ -z "$DOCKER_COMPOSE_CMD" ]; then
  echo "Docker Compose not found. Please install Docker and Docker Compose first."
  exit 1
fi

if ! docker ps >/dev/null 2>&1; then
  echo "Docker requires elevated permissions. Commands will be run with sudo."
  DOCKER_PREFIX="sudo"
fi

if [ ! -d "$APP_DIR/.git" ]; then
  git clone "$REPO_URL" "$APP_DIR"
else
  echo "Directory $APP_DIR already exists, skipping clone"
fi

cd "$APP_DIR"

mkdir -p nodered-data openccu-data

read -rp "Enter USB device for openCCU [default: /dev/ttyUSB0]: " OCCU_USB_DEVICE
OCCU_USB_DEVICE="${OCCU_USB_DEVICE:-/dev/ttyUSB0}"

read -rp "Enter Node-RED admin username [default: admin]: " NODERED_USER
NODERED_USER="${NODERED_USER:-admin}"

read -rsp "Enter Node-RED admin password: " NODERED_PASS
echo
if [ -z "$NODERED_PASS" ]; then
  echo "Password must not be empty."
  exit 1
fi

HASHED_PASS="$($DOCKER_PREFIX docker run --rm nodered/node-red:latest node -e "console.log(require('bcryptjs').hashSync(process.argv[1], 8))" "$NODERED_PASS")"

cat > .env <<EOF
OCCU_USB_DEVICE=$OCCU_USB_DEVICE
EOF

cat > nodered-data/settings.js <<EOF
module.exports = {
    flowFile: 'flows.json',
    credentialSecret: false,
    adminAuth: {
        type: "credentials",
        users: [{
            username: "$NODERED_USER",
            password: "$HASHED_PASS",
            permissions: "*"
        }]
    }
}
EOF

$DOCKER_PREFIX $DOCKER_COMPOSE_CMD up -d

echo "Containers started successfully."
echo "Node-RED: http://localhost:1880"
echo "openCCU:  http://localhost"
echo "openCCU USB device: $OCCU_USB_DEVICE"