#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/gery0815/iot-clients.git"
APP_DIR="iot-clients"

PKG_PREFIX=""

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    PKG_PREFIX="sudo"
  else
    echo "This script needs root privileges to install missing packages."
    echo "Please run as root or install 'sudo'."
    exit 1
  fi
fi

ensure_prerequisites() {
  local need_update=0

  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi

  if [ "${ID:-}" != "debian" ] && [[ "${ID_LIKE:-}" != *"debian"* ]]; then
    if ! command -v git >/dev/null 2>&1 || ! command -v docker >/dev/null 2>&1; then
      echo "Automatic dependency installation is supported only on Debian-based systems."
      echo "Please install git, docker, and docker compose manually, then rerun this script."
      exit 1
    fi
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    need_update=1
  fi
  if ! command -v docker >/dev/null 2>&1; then
    need_update=1
  fi
  if ! command -v docker-compose >/dev/null 2>&1; then
    if ! docker compose version >/dev/null 2>&1; then
      need_update=1
    fi
  fi

  if [ "$need_update" -eq 1 ]; then
    echo "Installing missing prerequisites (git, docker, docker compose)..."
    $PKG_PREFIX apt-get update
  fi

  if ! command -v git >/dev/null 2>&1; then
    $PKG_PREFIX apt-get install -y git
  fi

  if ! command -v docker >/dev/null 2>&1; then
    $PKG_PREFIX apt-get install -y docker.io
    if command -v systemctl >/dev/null 2>&1; then
      $PKG_PREFIX systemctl enable --now docker >/dev/null 2>&1 || true
    fi
  fi

  if ! docker compose version >/dev/null 2>&1; then
    if apt-cache show docker-compose-plugin >/dev/null 2>&1; then
      $PKG_PREFIX apt-get install -y docker-compose-plugin
    fi
  fi

  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    $PKG_PREFIX apt-get install -y docker-compose
  fi
}

ensure_prerequisites

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
  echo "Docker Compose not found after dependency installation."
  echo "Please install Docker Compose manually and rerun this script."
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

$DOCKER_PREFIX $DOCKER_COMPOSE_CMD pull nodered portainer
$DOCKER_PREFIX $DOCKER_COMPOSE_CMD build --pull openccu
$DOCKER_PREFIX $DOCKER_COMPOSE_CMD up -d

echo "Project updated and containers restarted successfully."
echo "Node-RED: http://localhost:1880"
echo "openCCU:  http://localhost"
echo "Portainer: http://localhost:9000 (HTTPS: https://localhost:9443)"
echo "openCCU USB device: $OCCU_USB_DEVICE"
echo
echo "Host requirement for Homematic RF modules: install the piVCCU kernel modules on the host OS, not in the container."