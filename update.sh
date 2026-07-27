#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/gery0815/iot-clients.git"
APP_DIR="iot-clients"
DEFAULT_NODERED_IMAGE="nodered/node-red:latest"
NODERED_PULL_TIMEOUT_SECONDS="${NODERED_PULL_TIMEOUT_SECONDS:-900}"
NODERED_HASH_TIMEOUT_SECONDS="${NODERED_HASH_TIMEOUT_SECONDS:-120}"

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

setup_host_pivccu_modules() {
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi

  if [ "${ID:-}" != "debian" ] && [[ "${ID_LIKE:-}" != *"debian"* ]]; then
    echo "Skipping automatic piVCCU host module setup (supported on Debian-based systems only)."
    echo "Please install piVCCU host modules manually on this host."
    return 0
  fi

  echo "Configuring piVCCU host modules and dependencies..."
  $PKG_PREFIX apt-get update
  $PKG_PREFIX apt-get install -y wget ca-certificates build-essential bison flex libssl-dev gpg

  wget -qO - https://apt.pivccu.de/piVCCU/public.key | $PKG_PREFIX gpg --dearmor -o /usr/share/keyrings/pivccu-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/pivccu-archive-keyring.gpg] https://apt.pivccu.de/piVCCU stable main" | $PKG_PREFIX tee /etc/apt/sources.list.d/pivccu.list >/dev/null

  $PKG_PREFIX apt-get update
  $PKG_PREFIX apt-get install -y pivccu-modules-dkms

  $PKG_PREFIX rm -f /etc/udev/rules.d/10-hmiprfusb.rules

  if command -v systemctl >/dev/null 2>&1; then
    $PKG_PREFIX systemctl enable --now pivccu-dkms >/dev/null 2>&1 || true
  fi
  $PKG_PREFIX service pivccu-dkms start >/dev/null 2>&1 || true

  echo "eq3_char_loop" | $PKG_PREFIX tee /etc/modules-load.d/eq3_char_loop.conf >/dev/null
  if ! $PKG_PREFIX modprobe eq3_char_loop; then
    echo "Warning: could not load eq3_char_loop immediately. It is configured to autoload on next boot."
  fi
}

verify_host_pivccu_setup() {
  echo "Verifying host piVCCU setup..."

  if command -v systemctl >/dev/null 2>&1; then
    if $PKG_PREFIX systemctl is-enabled pivccu-dkms >/dev/null 2>&1; then
      echo "pivccu-dkms autostart: enabled"
    else
      echo "pivccu-dkms autostart: not enabled"
    fi

    if $PKG_PREFIX systemctl is-active pivccu-dkms >/dev/null 2>&1; then
      echo "pivccu-dkms status: active"
    else
      echo "pivccu-dkms status: not active"
    fi
  else
    if $PKG_PREFIX service pivccu-dkms status >/dev/null 2>&1; then
      echo "pivccu-dkms status: active"
    else
      echo "pivccu-dkms status: status check unavailable or inactive"
    fi
  fi

  if command -v lsmod >/dev/null 2>&1 && lsmod | grep -q '^eq3_char_loop'; then
    echo "Kernel module eq3_char_loop: loaded"
  else
    echo "Kernel module eq3_char_loop: not loaded now (autoload configured for next boot)"
  fi
}

setup_host_pivccu_modules
verify_host_pivccu_setup

pull_nodered_image_or_prompt() {
  local image="$1"

  echo "Pulling Node-RED image: $image"
  echo "This can take several minutes on first run."
  if $DOCKER_PREFIX timeout "$NODERED_PULL_TIMEOUT_SECONDS" docker pull "$image"; then
    NODERED_IMAGE="$image"
    return 0
  fi

  echo "Failed to pull '$image'."
  echo "Your system may require a different Node-RED image tag."

  while true; do
    read -rp "Enter a compatible Node-RED image tag (or press Enter to abort): " image
    if [ -z "$image" ]; then
      return 1
    fi

    echo "Trying '$image'..."
    if $DOCKER_PREFIX timeout "$NODERED_PULL_TIMEOUT_SECONDS" docker pull "$image"; then
      NODERED_IMAGE="$image"
      return 0
    fi

    echo "Failed to pull '$image'. Please try another tag."
  done
}

generate_nodered_bcrypt_hash() {
  local password="$1"
  local hash
  local timeout_cmd=()

  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd=(timeout "$NODERED_HASH_TIMEOUT_SECONDS")
  fi

  if ! hash="$($DOCKER_PREFIX "${timeout_cmd[@]}" docker run --rm --entrypoint node "$NODERED_IMAGE" -e "console.log(require('bcryptjs').hashSync(process.argv[1], 8))" "$password")"; then
    echo "Failed to generate Node-RED password hash in container '$NODERED_IMAGE'."
    echo "Try a different NODERED_IMAGE tag or rerun with: NODERED_HASH_TIMEOUT_SECONDS=300 ./update.sh"
    return 1
  fi

  printf '%s' "$hash"
}

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
NODERED_IMAGE="${NODERED_IMAGE:-$DEFAULT_NODERED_IMAGE}"
if [ -f .env ]; then
  CURRENT_USB_DEVICE="$(grep '^OCCU_USB_DEVICE=' .env | cut -d= -f2- || true)"
  CURRENT_USB_DEVICE="${CURRENT_USB_DEVICE:-/dev/ttyUSB0}"

  EXISTING_NODERED_IMAGE="$(grep '^NODERED_IMAGE=' .env | cut -d= -f2- || true)"
  NODERED_IMAGE="${EXISTING_NODERED_IMAGE:-$DEFAULT_NODERED_IMAGE}"
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

  if ! pull_nodered_image_or_prompt "$NODERED_IMAGE"; then
    echo "Aborted because no compatible Node-RED image was provided."
    exit 1
  fi

  if ! HASHED_PASS="$(generate_nodered_bcrypt_hash "$NODERED_PASS")"; then
    exit 1
  fi

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

cat > .env <<EOF
OCCU_USB_DEVICE=$OCCU_USB_DEVICE
NODERED_IMAGE=$NODERED_IMAGE
EOF

$DOCKER_PREFIX $DOCKER_COMPOSE_CMD pull nodered portainer
$DOCKER_PREFIX $DOCKER_COMPOSE_CMD build --pull openccu
$DOCKER_PREFIX $DOCKER_COMPOSE_CMD up -d

echo "Compose was started in detached mode (-d)."
echo "Any long wait before this point is from image pull/build steps."

echo "Project updated and containers restarted successfully."
echo "Node-RED: http://localhost:1880"
echo "openCCU:  http://localhost"
echo "Portainer: http://localhost:9000 (HTTPS: https://localhost:9443)"
echo "openCCU USB device: $OCCU_USB_DEVICE"
echo
echo "Host requirement for Homematic RF modules: install the piVCCU kernel modules on the host OS, not in the container."