#!/usr/bin/env bash
# Cost estimation (pay-as-you-go, PostPaid).
# All template Parameters without default values must be passed via environment variables:
#   APP_NAME, INSTANCE_TYPE, PASSWORD (required)
#   SYSTEM_DISK_SIZE (default 40), BACKEND_PORT (default 8080)
# With RDS (WITH_RDS=1): DB_PASSWORD required; optional DB_INSTANCE_CLASS / DB_INSTANCE_STORAGE / DB_NAME / DB_ACCOUNT
# Note: WITH_RDS is auto-detected from template URL (contains "_rds") or DB_PASSWORD env var.
#       Explicit WITH_RDS=1 always takes precedence.
# Usage:
#   APP_NAME=myapp INSTANCE_TYPE=ecs.e-c1m2.large PASSWORD='Tmp_Pwd_For_Pricing!1' \
#     ./estimate_cost.sh <region> <template-url>
set -uo pipefail

usage() { echo "Usage: APP_NAME=... INSTANCE_TYPE=... PASSWORD=... $0 <region> <template-url>" >&2; exit 64; }
[ $# -eq 2 ] || usage
REGION="$1"; TPL_URL="$2"
: "${APP_NAME:?missing APP_NAME}"
: "${INSTANCE_TYPE:?missing INSTANCE_TYPE}"
: "${PASSWORD:?missing PASSWORD}"
DISK="${SYSTEM_DISK_SIZE:-40}"
PORT="${BACKEND_PORT:-8080}"

# Export TPL_URL so _build_params.sh can auto-detect RDS from template filename
export TPL_URL

WITH_RDS="${WITH_RDS:-0}"
if [ "$WITH_RDS" = "1" ]; then
  : "${DB_PASSWORD:?missing DB_PASSWORD (WITH_RDS=1)}"
fi

# Pre-fill RDS defaults (harmless if WITH_RDS=0; required if auto-detected later).
# DB_PASSWORD must be set by caller when RDS is intended; _build_params.sh validates.
DB_INSTANCE_CLASS="${DB_INSTANCE_CLASS:-mysql.n2.medium.1}"
DB_INSTANCE_STORAGE="${DB_INSTANCE_STORAGE:-20}"
DB_NAME="${DB_NAME:-appdb}"
DB_ACCOUNT="${DB_ACCOUNT:-appuser}"

# Use a minimal UserData placeholder for pricing (pricing doesn't care about script content; RDS templates don't have this parameter)
USERDATA="${USERDATA:-#!/bin/bash}"

# Build parameter array dynamically (shared logic)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/build_params.sh"

echo "[estimate] === PostPaid (pay-as-you-go) ===" >&2
build_ros_params
aliyun ros GetTemplateEstimateCost \
  --RegionId "$REGION" \
  --TemplateURL "$TPL_URL" \
  "${PARAMS[@]}"
echo >&2
