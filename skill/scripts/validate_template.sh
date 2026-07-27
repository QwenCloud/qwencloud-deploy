#!/usr/bin/env bash
# Validate ROS template. Uses --TemplateURL (OSS URL) to avoid WAF blocking.
set -uo pipefail

usage() { echo "Usage: $0 <region> <template-url>" >&2; exit 64; }
[ $# -eq 2 ] || usage
REGION="$1"; TPL_URL="$2"

echo "[validate] aliyun ros ValidateTemplate --RegionId $REGION --TemplateURL $TPL_URL"
OUT=$(aliyun ros ValidateTemplate --RegionId "$REGION" --TemplateURL "$TPL_URL" 2>&1)
CODE=$?
if [ $CODE -ne 0 ]; then
  echo "[validate] FAILED:" >&2
  echo "$OUT" >&2
  exit $CODE
fi
echo "$OUT"
echo "[validate] OK"
