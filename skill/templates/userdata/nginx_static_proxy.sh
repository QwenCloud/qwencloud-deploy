#!/bin/bash
# qwencloud · Nginx static hosting + /api/ reverse proxy to backend
# This snippet is injected into ECS UserData header by generate_template.py.
# Placeholders (replaced by generate_template.py):
#   __FRONTEND_ARTIFACT_URL__  OSS signed URL of frontend dist archive (http GET)
#   __BACKEND_PORT__           Backend service listening port (e.g. 8080)
set -euxo pipefail

LOG=/var/log/qwencloud-bootstrap.log
exec > >(tee -a "$LOG") 2>&1
echo "[$(date -u +%FT%TZ)] === qwencloud nginx bootstrap start ==="

# 1. Install Nginx
if ! command -v nginx >/dev/null 2>&1; then
  if command -v dnf >/dev/null 2>&1; then dnf install -y nginx
  elif command -v yum >/dev/null 2>&1; then yum install -y nginx
  elif command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get install -y nginx
  else echo "no supported package manager"; exit 1
  fi
fi

# 2. Pull frontend build artifacts (if any)
# Note: FRONTEND_URL is replaced by generate_template.py before packaging: real signed URL if artifacts exist, empty string if no frontend
FRONTEND_URL='__FRONTEND_ARTIFACT_URL__'
mkdir -p /var/www/frontend
if [ -n "$FRONTEND_URL" ]; then
  curl -fsSL "$FRONTEND_URL" -o /tmp/frontend.tar.gz
  tar -xzf /tmp/frontend.tar.gz -C /var/www/frontend --strip-components=0
  rm -f /tmp/frontend.tar.gz
else
  cat > /var/www/frontend/index.html <<'HTML'
<!doctype html><meta charset=utf-8><title>qwencloud</title>
<h1>ECS is up. Awaiting frontend artifact.</h1>
HTML
fi

# 3. Write site config: port 80 root points to frontend, /api/ reverse-proxies to backend
cat > /etc/nginx/conf.d/qwencloud.conf <<NGINX
server {
    listen 80 default_server;
    server_name _;
    root /var/www/frontend;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:__BACKEND_PORT__;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 60s;
    }

    location = /healthz { return 200 "ok\n"; }
}
NGINX

# Remove default server (avoid conflicts)
[ -f /etc/nginx/conf.d/default.conf ] && mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak || true

nginx -t
systemctl enable nginx
systemctl restart nginx

echo "[$(date -u +%FT%TZ)] nginx ready"
