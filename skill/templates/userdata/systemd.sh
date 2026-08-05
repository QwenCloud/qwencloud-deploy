#!/bin/bash
# qwencloud · systemd managed app
# Placeholders:
#   __APP_ARTIFACT_URL__   OSS signed URL of app artifact tar.gz
#   __APP_RUNTIME__        none | java | node | python
#   __START_COMMAND__          Full startup command (relative to /opt/qwencloud), e.g.
#                              ./server / "python3 app.py" / "java -jar app.jar" /
#                              "node server.js" / "gunicorn -b :8080 app:app"
#   __APP_PORT__           App listening port
set -euxo pipefail

LOG=/var/log/qwencloud-bootstrap.log
exec >> "$LOG" 2>&1
echo "[$(date -u +%FT%TZ)] === qwencloud systemd bootstrap start ==="

APP_URL="__APP_ARTIFACT_URL__"
RUNTIME="__APP_RUNTIME__"
ENTRY="__START_COMMAND__"
PORT="__APP_PORT__"

# 1. Install runtime
case "$RUNTIME" in
  java)
    if ! command -v java >/dev/null 2>&1; then
      if command -v dnf >/dev/null 2>&1; then dnf install -y java-17-openjdk-headless
      else yum install -y java-17-openjdk-headless; fi
    fi
    ;;
  node)
    if ! command -v node >/dev/null 2>&1; then
      # Install Node from the distro's GPG-signed package repos (no `curl … | bash` remote code execution).
      # Order: (1) plain dnf install (on Alibaba Cloud Linux 3, nodejs 20 is a standalone package in
      #        alinux3-updates); (2) if no standalone package, enable a nodejs module stream and install;
      #        (3) older systems fall back to yum.
      if command -v dnf >/dev/null 2>&1; then
        if ! dnf install -y nodejs npm; then
          if dnf -q module list nodejs >/dev/null 2>&1; then
            dnf -y module reset nodejs || true
            # prefer 20, otherwise fall back to whatever default stream the image offers
            dnf -y module enable nodejs:20 || dnf -y module enable nodejs || true
            dnf install -y nodejs npm
          fi
        fi
      else
        yum install -y nodejs npm
      fi
    fi
    if ! command -v yarn >/dev/null 2>&1; then
      npm install -g yarn
    fi
    ;;
  python)
    if ! command -v python3 >/dev/null 2>&1; then
      yum install -y python3 python3-pip
    fi
    ;;
  none)
    : # No runtime installation needed (static binary, or runtime already exists)
    ;;
  *)
    echo "[warn] unknown runtime '$RUNTIME', skipping runtime install"
    ;;
esac

# 2. Pull artifacts
mkdir -p /opt/qwencloud
cd /opt/qwencloud
curl -fsSL "$APP_URL" -o app.tar.gz
tar -xzf app.tar.gz
rm -f app.tar.gz

# 2b. Java JAR-name safeguard: Maven/Gradle usually produce a version-stamped JAR name,
# but ENTRY often hardcodes a fixed name such as "java -jar app.jar". If ENTRY references
# a JAR that does not exist, symlink the real runnable JAR to that expected name so the
# service starts regardless of the artifact's actual filename.
if [ "$RUNTIME" = "java" ]; then
  # The JAR token in ENTRY = the argument right after "-jar" (default app.jar).
  WANT_JAR="$(printf '%s ' $ENTRY | awk '{for(i=1;i<NF;i++) if($i=="-jar"){print $(i+1); exit}}')"
  [ -n "$WANT_JAR" ] || WANT_JAR="app.jar"
  WANT_BASE="$(basename "$WANT_JAR")"
  if [ ! -f "/opt/qwencloud/$WANT_BASE" ]; then
    # Pick the largest *.jar (the runnable fat JAR), excluding sources/javadoc/plain jars.
    # Use stat for portability (GNU find -printf may be missing on minimal images).
    REAL_JAR="$(find /opt/qwencloud -maxdepth 3 -type f -name '*.jar' \
      ! -name '*-sources.jar' ! -name '*-javadoc.jar' ! -name 'original-*.jar' 2>/dev/null \
      | while read -r f; do printf '%s\t%s\n' "$(stat -c%s "$f" 2>/dev/null || echo 0)" "$f"; done \
      | sort -rn | head -1 | cut -f2)"
    if [ -n "$REAL_JAR" ]; then
      echo "[info] JAR '$WANT_BASE' not found; linking real JAR: $REAL_JAR -> /opt/qwencloud/$WANT_BASE"
      ln -sf "$REAL_JAR" "/opt/qwencloud/$WANT_BASE"
    else
      echo "[error] no runnable JAR found under /opt/qwencloud; app will fail to start"
    fi
  fi
fi

# python: install dependencies
if [ "$RUNTIME" = "python" ] && [ -f requirements.txt ]; then
  python3 -m pip install --no-cache-dir -r requirements.txt
fi
# node: install dependencies (when artifact includes package.json)
if [ "$RUNTIME" = "node" ] && [ -f package.json ]; then
  yarn install --production
fi

# 3. Parse startup command
# ENTRY is the "full startup command" and the sole source of the command; the script does NOT
# inject any interpreter based on runtime — it only resolves the first token (argv[0]) to an
# absolute path, because systemd ExecStart requires argv[0] to be an absolute path.
# This way, whether it's ./server / "python3 run.py" / "java -jar app.jar" / "gunicorn app:app",
# it runs exactly as the user specified — no collision between "auto prefix" and "user prefix".
set -- $ENTRY
ARGV0="$1"; shift || true
case "$ARGV0" in
  /*)
    : ;;                                    # Already an absolute path, use as-is
  */*)
    # Relative path containing / (./server, subdir/app) → build absolute path; cannot use command -v as it returns relative paths as-is
    ARGV0="/opt/qwencloud/${ARGV0#./}"
    chmod +x "$ARGV0" 2>/dev/null || true
    ;;
  *)
    if command -v "$ARGV0" >/dev/null 2>&1; then
      ARGV0="$(command -v "$ARGV0")"        # Interpreter/tool on PATH (python3 / node / java / gunicorn ...)
    else
      ARGV0="/opt/qwencloud/$ARGV0"         # Executable in the artifact (bare filename, e.g. server)
      chmod +x "$ARGV0" 2>/dev/null || true
    fi ;;
esac
EXEC="$ARGV0 $*"

# 4. Write systemd unit
cat > /etc/systemd/system/qwencloud-app.service <<UNIT
[Unit]
Description=qwencloud app
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/opt/qwencloud
Environment=PORT=${PORT}
EnvironmentFile=-/etc/qwencloud/db.env
ExecStart=${EXEC}
Restart=always
RestartSec=3
StandardOutput=append:/var/log/qwencloud-app.log
StandardError=append:/var/log/qwencloud-app.log

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable qwencloud-app
systemctl restart qwencloud-app

echo "[$(date -u +%FT%TZ)] systemd app up"
