#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${1:-}"

if [ -z "$REPO_URL" ]; then
  echo "Usage: $0 <git-repository-url>"
  exit 1
fi

APP_DIR="$(basename "$REPO_URL" .git)"

if [ ! -d "$APP_DIR" ]; then
  git clone "$REPO_URL"
else
  echo "Directory $APP_DIR already exists, skipping clone"
fi

cd "$APP_DIR"

DOCKER_CMD=""
if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    DOCKER_CMD="docker compose"
  fi
fi

if [ -z "$DOCKER_CMD" ] && command -v docker-compose >/dev/null 2>&1; then
  DOCKER_CMD="docker-compose"
fi

if [ -z "$DOCKER_CMD" ]; then
  echo "Docker Compose not found. Please install Docker and Docker Compose first."
  exit 1
fi

if ! docker ps >/dev/null 2>&1; then
  echo "Docker requires elevated permissions. Retrying with sudo..."
  sudo $DOCKER_CMD up -d
else
  $DOCKER_CMD up -d
fi

echo "Containers started successfully."
echo "Node-RED: http://localhost:1880"
echo "openCCU:  http://localhost"