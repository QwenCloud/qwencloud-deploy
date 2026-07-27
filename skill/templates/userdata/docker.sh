#!/bin/bash
# qwencloud · Docker backend bootstrap
# Placeholders:
#   __BACKEND_ARTIFACT_URL__   OSS signed URL of backend image tar.gz (docker save output) or docker-compose.yml + build context tar.gz
#   __BACKEND_MODE__           docker-image | docker-compose
#   __BACKEND_PORT__           Backend container listening port (reverse-proxied by Nginx)
#   __BACKEND_IMAGE_NAME__     Image name:tag after docker load in docker-image mode (e.g. myapp:latest)
set -euxo pipefail

LOG=/var/log/qwencloud-bootstrap.log
exec >> "$LOG" 2>&1
echo "[$(date -u +%FT%TZ)] === qwencloud docker bootstrap start ==="

# 1. Install Docker
if ! command -v docker >/dev/null 2>&1; then
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y docker
  elif command -v yum >/dev/null 2>&1; then
    yum install -y docker
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update && apt-get install -y docker.io
  fi
fi
systemctl enable docker
systemctl start docker

BACKEND_URL="__BACKEND_ARTIFACT_URL__"
BACKEND_MODE="__BACKEND_MODE__"
BACKEND_PORT="__BACKEND_PORT__"
IMAGE_NAME="__BACKEND_IMAGE_NAME__"

mkdir -p /opt/qwencloud
cd /opt/qwencloud
curl -fsSL "$BACKEND_URL" -o backend.tar.gz

# If RDS bootstrap wrote db.env, mount it into the container at startup
DB_ENV_OPT=""
[ -f /etc/qwencloud/db.env ] && DB_ENV_OPT="--env-file /etc/qwencloud/db.env"

if [ "$BACKEND_MODE" = "docker-image" ]; then
  # Extract and docker load
  tar -xzf backend.tar.gz
  docker load -i image.tar
  # Write systemd unit for persistent management
  cat > /etc/systemd/system/qwencloud-app.service <<UNIT
[Unit]
Description=qwencloud app container
After=docker.service
Requires=docker.service

[Service]
Restart=always
ExecStartPre=-/usr/bin/docker rm -f qwencloud-app
ExecStart=/usr/bin/docker run --rm --name qwencloud-app -p ${BACKEND_PORT}:${BACKEND_PORT} ${DB_ENV_OPT} ${IMAGE_NAME}
ExecStop=/usr/bin/docker stop qwencloud-app

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable qwencloud-app
  systemctl restart qwencloud-app

elif [ "$BACKEND_MODE" = "docker-compose" ]; then
  # Extract (contains docker-compose.yml and build context or pre-built image tar)
  tar -xzf backend.tar.gz
  # Install docker compose plugin (if not already available)
  if ! docker compose version >/dev/null 2>&1; then
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -fsSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
  fi
  # compose auto-loads .env from the same directory; if RDS env exists, export it to .env
  if [ -f /etc/qwencloud/db.env ]; then
    cp /etc/qwencloud/db.env ./.env
  fi
  docker compose -f docker-compose.yml up -d
fi

echo "[$(date -u +%FT%TZ)] docker backend up"
