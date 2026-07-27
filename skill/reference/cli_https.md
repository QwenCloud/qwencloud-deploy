# HTTPS · certbot via Cloud Assistant

Complete command templates for Step H5 (certificate issuance + Nginx HTTPS config).

## HTTPS · certbot via Cloud Assistant (Step H5)

### Install certbot + dig (one RunCommand, timeout 120s)

Alibaba Cloud Linux uses yum; `epel-aliyuncs-release` may already exist (conflicts with `epel-release`). `bind-utils`
provides `dig` (needed by the auth-hook to verify DNS propagation).

```bash
PAGER=cat aliyun ecs RunCommand --RegionId "$REGION" --InstanceId.1 "$INSTANCE_ID" \
  --Type RunShellScript --Timeout 120 --ContentEncoding PlainText \
  --CommandContent 'yum install -y certbot bind-utils 2>/dev/null || { pip3 install certbot && yum install -y bind-utils; }'
```

> ⚠️ Do NOT use base64 encoding for `--CommandContent` — Cloud Assistant executes
> the string directly as a shell script. Using base64 causes ECS to try to run the
> encoded string literally.

> ⚠️ Use `pip3 install certbot` as fallback if yum certbot is unavailable (common on
> Alibaba Cloud Linux where EPEL conflicts exist).

### Run certbot with self-polling auth-hook (one RunCommand, timeout 600s)

The auth-hook writes the ACME challenge token to a file, then polls authoritative NS until the TXT record propagates.
The agent creates the TXT record locally in parallel.

```bash
# Agent constructs this script with $DOMAIN and $EMAIL substituted literally:
SCRIPT='#!/bin/bash
set -uo pipefail
DOMAIN="example.com"
EMAIL="user@example.com"
CB=/etc/qwencloud/certbot
mkdir -p $CB/config $CB/work $CB/logs
LIVE="$CB/config/live/$DOMAIN"

# Kill stale certbot (from previous timeout) and clear lock + stale token
pkill -f certbot 2>/dev/null || true
rm -f $CB/config/.certbot.lock $CB/work/.certbot.lock $CB/logs/.certbot.lock
rm -f $CB/token.txt  # MUST delete old token so agent only reads THIS run's token

# Short-circuit if cert already valid (>7 days)
if [ -f "$LIVE/fullchain.pem" ] && openssl x509 -checkend 604800 -noout -in "$LIVE/fullchain.pem" 2>/dev/null; then
  echo "CERT_ALREADY_VALID"; exit 0
fi

# Write auth-hook (queries AUTHORITATIVE NS directly — bypasses public DNS propagation delay)
cat > $CB/auth-hook.sh << '''HOOK'''
#!/bin/bash
echo "${CERTBOT_VALIDATION}" > /etc/qwencloud/certbot/token.txt
FQDN="_acme-challenge.${CERTBOT_DOMAIN}"
# Resolve authoritative NS for the root domain (avoids public DNS cache delay)
ROOT=$(echo "${CERTBOT_DOMAIN}" | awk -F. '{n=NF; print $(n-1)"."$n}')
AUTH_NS=$(dig +short "$ROOT" NS 2>/dev/null | head -1 | sed 's/\.$//')
[ -z "$AUTH_NS" ] && AUTH_NS="dns1.hichina.com"
for i in $(seq 1 60); do
  sleep 3
  RESOLVED=$(dig +short "$FQDN" TXT @"$AUTH_NS" 2>/dev/null | tr -d "\"")
  [ -z "$RESOLVED" ] && continue
  echo "$RESOLVED" | grep -qF "${CERTBOT_VALIDATION}" && exit 0
done
echo "DNS_PROPAGATION_TIMEOUT" >&2; exit 1
HOOK
chmod +x $CB/auth-hook.sh

certbot certonly --manual --preferred-challenges dns \
  -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" \
  --cert-name "$DOMAIN" \
  --config-dir $CB/config --work-dir $CB/work --logs-dir $CB/logs \
  --manual-auth-hook $CB/auth-hook.sh --keep-until-expiring

if [ -f "$LIVE/fullchain.pem" ]; then echo "CERT_ISSUED"; else echo "CERT_FAILED"; exit 1; fi'

PAGER=cat aliyun ecs RunCommand --RegionId "$REGION" --InstanceId.1 "$INSTANCE_ID" \
  --Type RunShellScript --Timeout 600 --ContentEncoding PlainText \
  --CommandContent "$SCRIPT"
```

> ⚠️ **Token freshness**: every `certbot certonly` generates a **new** challenge
> token. The script above deletes the old token file before starting certbot.
> The agent MUST poll for the token file AFTER launching this RunCommand and use
> the value it reads to create/update the TXT record. Never reuse a token from a
> previous run — if certbot was restarted, the old TXT value is invalid.

> ⚠️ **Stale lock**: if a previous certbot timed out, the lock file remains and
> blocks the next run ("Another instance of Certbot is already running"). The script
> above kills stale processes and removes lock files before starting.

### Poll for token + create TXT (agent runs locally, parallel with step above)

Submit ONE RunCommand that waits for the token file on the ECS (avoids repeated RunCommand round-trips which each take
5–10s of Cloud Assistant overhead):

```bash
# Single self-polling read command (timeout 120s — token usually appears in <10s):
PAGER=cat aliyun ecs RunCommand --RegionId "$REGION" --InstanceId.1 "$INSTANCE_ID" \
  --Type RunShellScript --Timeout 120 --ContentEncoding PlainText \
  --CommandContent 'for i in $(seq 1 24); do [ -s /etc/qwencloud/certbot/token.txt ] && cat /etc/qwencloud/certbot/token.txt && exit 0; sleep 5; done; exit 1'
```

Then **wait 15s** before first `DescribeInvocations` (Cloud Assistant needs time to dispatch + execute). Poll
`DescribeInvocations` every 10s until `Finished`.

> ⚠️ **Do NOT** submit a new RunCommand each poll cycle. Each RunCommand has ~5–10s
> dispatch overhead; submitting 12 short-lived reads wastes ~2 minutes. Instead, submit
> ONE command that loops internally, then poll its status from the local host.

```bash
# After getting the token from DescribeInvocations output:
MODE=dns-txt DOMAIN="$DOMAIN" TXT_NAME="_acme-challenge" \
  TXT_VALUE="$TOKEN" bash scripts/setup_domain.sh
```

### Configure Nginx for HTTPS (one RunCommand, timeout 60s)

```bash
# Agent substitutes $DOMAIN and $PORT:
PAGER=cat aliyun ecs RunCommand --RegionId "$REGION" --InstanceId.1 "$INSTANCE_ID" \
  --Type RunShellScript --Timeout 60 --ContentEncoding PlainText \
  --CommandContent '#!/bin/bash
DOMAIN="example.com"
CERT=/etc/qwencloud/certbot/config/live/$DOMAIN/fullchain.pem
KEY=/etc/qwencloud/certbot/config/live/$DOMAIN/privkey.pem
PORT=3000

cat > /etc/nginx/conf.d/qwencloud-ssl.conf << EOF
server { listen 80; server_name $DOMAIN; return 301 https://\$host\$request_uri; }
server {
    listen 443 ssl http2; server_name $DOMAIN;
    ssl_certificate $CERT; ssl_certificate_key $KEY;
    ssl_protocols TLSv1.2 TLSv1.3;
    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
[ -f /etc/nginx/conf.d/qwencloud.conf ] && mv /etc/nginx/conf.d/qwencloud.conf{,.bak}
nginx -t && systemctl reload nginx && echo "NGINX_OK"'
```

### Cleanup TXT record

```bash
MODE=dns-txt-clean DOMAIN="$DOMAIN" TXT_NAME="_acme-challenge" bash scripts/setup_domain.sh
```

