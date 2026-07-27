#!/usr/bin/env bash
# ECS (+ optional RDS) stock query (pay-as-you-go, PostPaid).
# Usage:
#   ./check_stock.sh <region> <instance-type> [min-zones=1]
# When RDS is included, set environment variables (outputs ECS ∩ RDS availability zone intersection):
#   DB_INSTANCE_CLASS=mysql.n2.medium.1   Required (used to verify RDS support per zone)
#   DB_CATEGORY=Basic                     Optional, default Basic (basic edition / single-node)
#   DB_STORAGE_TYPE=cloud_essd            Optional, default cloud_essd (must match template)
#   DB_ENGINE_VERSION=8.0                 Optional, default 8.0 (must match template/instance class)
# Exit codes:
#   0  At least min-zones zones have stock (intersection when RDS included)
#   1  Insufficient stock
set -uo pipefail

usage() { echo "Usage: $0 <region> <instance-type> [min-zones=1]" >&2; exit 64; }
[ $# -ge 2 ] || usage
REGION="$1"; TYPE="$2"
MIN_ZONES="${3:-1}"

# --- ECS availability zones ---
ECS_OUT=$(aliyun ecs DescribeAvailableResource \
  --RegionId "$REGION" \
  --DestinationResource InstanceType \
  --InstanceType "$TYPE" \
  --InstanceChargeType PostPaid 2>&1) || { echo "$ECS_OUT" >&2; exit 2; }

ECS_ZONES=$(echo "$ECS_OUT" | python3 -c "
import json, sys
data = json.load(sys.stdin)
zones = data.get('AvailableZones', {}).get('AvailableZone', [])
ok = [z['ZoneId'] for z in zones if z.get('Status') in ('Available','WithStock')]
print('\n'.join(ok))
")
echo "[stock] ECS zones with stock: $ECS_ZONES"

# --- RDS per-zone verification (optional) ---
# DescribeAvailableZones only goes down to storage type, cannot get instance classes;
# must use DescribeAvailableClasses to verify per zone. Only checks zones where ECS
# has stock, so the result is the ECS ∩ RDS intersection.
if [ -n "${DB_INSTANCE_CLASS:-}" ]; then
  DB_CATEGORY="${DB_CATEGORY:-Basic}"
  DB_STORAGE_TYPE="${DB_STORAGE_TYPE:-cloud_essd}"
  DB_ENGINE_VERSION="${DB_ENGINE_VERSION:-8.0}"
  FINAL_ZONES=""
  for z in $ECS_ZONES; do
    CLS_OUT=$(aliyun rds DescribeAvailableClasses \
      --RegionId "$REGION" --ZoneId "$z" \
      --Engine MySQL --EngineVersion "$DB_ENGINE_VERSION" \
      --Category "$DB_CATEGORY" --DBInstanceStorageType "$DB_STORAGE_TYPE" \
      --CommodityCode bards --OrderType BUY 2>/dev/null) || continue
    if echo "$CLS_OUT" | grep -qF "\"$DB_INSTANCE_CLASS\""; then
      FINAL_ZONES="${FINAL_ZONES}${z}"$'\n'
    fi
  done
  FINAL_ZONES=$(printf '%s' "$FINAL_ZONES" | grep . || true)
  echo "[stock] RDS ($DB_INSTANCE_CLASS / $DB_CATEGORY / $DB_STORAGE_TYPE) ∩ ECS zones: $FINAL_ZONES"
else
  FINAL_ZONES="$ECS_ZONES"
fi

COUNT=$(echo "$FINAL_ZONES" | grep -c . || true)

if ! [[ "$COUNT" =~ ^[0-9]+$ ]]; then
  echo "[stock] Failed to parse stock data (COUNT=$COUNT)" >&2
  exit 2
fi

echo "[stock] Available zone count: $COUNT  (need >= $MIN_ZONES)"
echo "[stock] Available zones: $FINAL_ZONES"

if [ "$COUNT" -lt "$MIN_ZONES" ]; then
  echo "[stock] Insufficient stock. Please change instance type or region." >&2
  exit 1
fi
exit 0
