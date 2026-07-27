#!/usr/bin/env bash
# Pre-flight check: whether aliyun CLI is installed, has a valid profile, region is configured, AK identity probe.
#
# Usage:
#   bash check_env.sh
#
# Exit codes:
#   0 Passed
#   2 CLI not installed / version too old
#   3 Profile / AK-SK invalid
#   4 (unused) region defaults to ap-southeast-1 when not configured
#   5 ros / ecs / oss subcommands not available
#   6 AK identity probe failed

set -uo pipefail

err() { echo "[check_env] ERROR: $*" >&2; }
ok()  { echo "[check_env] OK: $*"; }

# 1) aliyun CLI
if ! command -v aliyun >/dev/null 2>&1; then
  err "aliyun CLI not detected. Please install first:"
  err "  brew install aliyun-cli   # macOS"
  err "  or see https://help.aliyun.com/zh/cli/install-cli-on-macos"
  exit 2
fi
VERSION=$(aliyun version 2>/dev/null | head -1)
ok "aliyun CLI installed: $VERSION"
MAJOR=$(echo "$VERSION" | grep -oE '[0-9]+' | head -1)
if [ -n "$MAJOR" ] && [ "$MAJOR" -lt 3 ]; then
  err "aliyun CLI version too old (${VERSION}), requires 3.x+. Please upgrade."
  exit 2
fi

# 2) profile / AK-SK
LIST=$(aliyun configure list 2>&1) || {
  err "aliyun configure list failed: $LIST"
  exit 3
}
if ! echo "$LIST" | grep -qE '\*'; then
  err "No default profile found. Please run: aliyun configure --profile default"
  exit 3
fi
if ! echo "$LIST" | grep -qE 'Valid'; then
  err "Default profile credentials invalid. Please re-run: aliyun configure --profile default"
  err "$LIST"
  exit 3
fi
ok "AK/SK profile valid"

# 3) region (parsed from profile default region)
# International site: default to ap-southeast-1 (Singapore) when not configured,
# instead of failing — most international-site AKs operate there by default.
DEFAULT_REGION="ap-southeast-1"
REGION=$(aliyun configure get region 2>/dev/null | tr -d '[:space:]')
if [ -z "$REGION" ]; then
  REGION="$DEFAULT_REGION"
  ok "Default region not configured; using recommended default: $REGION (Singapore). To change: aliyun configure set --region <region>"
else
  ok "Default region: $REGION"
fi

# 4) Probe ROS / ECS / OSS subcommand availability
for prod in ros ecs oss; do
  if ! aliyun $prod help >/dev/null 2>&1; then
    err "aliyun $prod subcommand not available, please reinstall CLI or install plugin"
    exit 5
  fi
done
ok "ros / ecs / oss subcommands available"

# 4b) Verify the OSS *service* is actually activated (subcommand existing above
#     only proves the CLI has the plugin, NOT that the account enabled OSS).
#     A brand-new account without OSS activated fails later at `oss mb` with an
#     opaque error. Probe with a lightweight `oss ls`; if not activated, auto-
#     activate via OssAdmin OpenOssService (activation is free; usage is billed).
OSS_PROBE=$(aliyun oss ls 2>&1)
if echo "$OSS_PROBE" | grep -qiE 'not.*(enabled|activated|open)|has not.*opened|NoSuchService|please.*activate|未开通|开通'; then
  err "OSS service is not activated on this account. Activating automatically..."
  if OPEN_RESULT=$(aliyun ossadmin OpenOssService 2>&1) \
     || echo "$OPEN_RESULT" | grep -qiE 'already.*open|opened|ORDER.PROCESS|success'; then
    ok "OSS service activated (or already active)"
    # Re-probe to confirm.
    if aliyun oss ls >/dev/null 2>&1; then
      ok "OSS service reachable after activation"
    else
      err "OSS activation call succeeded but service still not reachable; it may take a moment. Retry the deploy shortly."
    fi
  else
    err "Failed to auto-activate OSS service:"
    err "$OPEN_RESULT"
    err "Please activate OSS manually: https://oss.console.aliyun.com/ (click Activate), then retry."
    exit 5
  fi
else
  ok "OSS service activated"
fi

# 5) Identity probe (mandatory) — STS is enabled by default for almost all AKs; failure usually means AK is expired
IDENT=$(aliyun sts GetCallerIdentity 2>&1)
if [ $? -ne 0 ]; then
  err "AK identity probe failed (aliyun sts GetCallerIdentity):"
  err "$IDENT"
  err "Possible causes: AK/SK expired, disabled, or explicitly Denied sts:GetCallerIdentity by RAM policy"
  exit 6
fi
ACCOUNT_ID=$(printf '%s' "$IDENT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('AccountId',''))" 2>/dev/null)
ARN=$(printf '%s' "$IDENT" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('Arn',''))" 2>/dev/null)
if [ -z "$ARN" ] || [ -z "$ACCOUNT_ID" ]; then
  err "Cannot parse GetCallerIdentity response (missing AccountId / Arn):"
  err "$IDENT"
  exit 6
fi
ok "AK identity: ${ARN} (account ${ACCOUNT_ID})"

echo
echo "REGION=$REGION"
echo "ACCOUNT_ID=$ACCOUNT_ID"
echo "IDENTITY_ARN=$ARN"
exit 0
