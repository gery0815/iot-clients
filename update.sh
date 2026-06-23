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
  echo "Project directory '$APP_DIR' not found. Cloning repository first..."
  git clone "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR"

mkdir -p nodered-data openccu-data

CURRENT_USB_DEVICE="/dev/ttyUSB0"
if [ -f .env ]; then
  CURRENT_USB_DEVICE="$(grep '^OCCU_USB_DEVICE=' .env | cut -d= -f2- || true)"
  CURRENT_USB_DEVICE="${CURRENT_USB_DEVICE:-/dev/ttyUSB0}"
fi

echo "Updating repository..."
git pull --ff-only

read -rp "Change openCCU USB device? (y/N): " CHANGE_USB
if [[ "$CHANGE_USB" =~ ^[Yy]$ ]]; then
  read -rp "Enter USB device for openCCU [current: $CURRENT_USB_DEVICE]: " OCCU_USB_DEVICE
  OCCU_USB_DEVICE="${OCCU_USB_DEVICE:-$CURRENT_USB_DEVICE}"
else
  OCCU_USB_DEVICE="$CURRENT_USB_DEVICE"
fi

cat > .env <<EOF
OCCU_USB_DEVICE=$OCCU_USB_DEVICE
EOF

read -rp "Change Node-RED admin credentials? (y/N): " CHANGE_CREDS
if [[ "$CHANGE_CREDS" =~ ^[Yy]$ ]]; then
  read -rp "Enter Node-RED admin username [default: admin]: " NODERED_USER
  NODERED_USER="${NODERED_USER:-admin}"

  read -rsp "Enter new Node-RED admin password: " NODERED_PASS
  echo
  if [ -z "$NODERED_PASS" ]; then
    echo "Password must not be empty."
    exit 1
  fi

  HASHED_PASS="$($DOCKER_PREFIX docker run --rm nodered/node-red:latest node -e "console.log(require('bcryptjs').hashSync(process.argv[1], 8))" "$NODERED_PASS")"

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
fi

$DOCKER_PREFIX $DOCKER_COMPOSE_CMD pull nodered
$DOCKER_PREFIX $DOCKER_COMPOSE_CMD build --pull openccu
$DOCKER_PREFIX $DOCKER_COMPOSE_CMD up -d

echo "Project updated and containers restarted successfully."
echo "Node-RED: http://localhost:1880"
echo "openCCU:  http://localhost"
echo "openCCU USB device: $OCCU_USB_DEVICE"
echo
echo "Host requirement for Homematic RF modules: install the piVCCU kernel modules on the host OS, not in the container."