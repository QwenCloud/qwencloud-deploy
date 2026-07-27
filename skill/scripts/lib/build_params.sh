#!/usr/bin/env bash
# Shared parameter construction logic, sourced by create_stack.sh and estimate_cost.sh.
# Required env vars before calling: APP_NAME, INSTANCE_TYPE, PASSWORD, DISK, PORT
# With RDS (WITH_RDS=1) also needs: DB_INSTANCE_CLASS, DB_INSTANCE_STORAGE, DB_NAME, DB_ACCOUNT, DB_PASSWORD
# Optional: ZONE_ID, USERDATA (placeholder only for estimate_cost)
# Optional: TPL_URL — when set, auto-detects WITH_RDS from template filename (contains "_rds")
#
# Output: PARAMS array

PARAMS=()
_add_param() {
  local n="$1" k="$2" v="$3"
  PARAMS+=("--Parameters.${n}.ParameterKey" "$k" "--Parameters.${n}.ParameterValue" "$v")
}

# ─── Auto-detect WITH_RDS from template URL or DB env vars ──────────────────
# Prevents the common pitfall where the caller forgets WITH_RDS=1 when using an
# RDS template, causing _build_params to inject UserDataScript — a parameter that
# doesn't exist in *_rds.yaml templates — resulting in UnknownUserParameter error.
_auto_detect_rds() {
  if [ "${WITH_RDS:-0}" = "1" ]; then
    return  # Explicitly set, no auto-detection needed
  fi

  local detected=0 reason=""

  # Signal 1: template URL contains "_rds" (strongest signal)
  if [ -n "${TPL_URL:-}" ] && echo "$TPL_URL" | grep -q '_rds'; then
    detected=1
    reason="template URL contains '_rds'"
  fi

  # Signal 2: DB_PASSWORD is set (DB-specific env var, unlikely to be set accidentally)
  if [ -n "${DB_PASSWORD:-}" ]; then
    detected=1
    reason="${reason:+$reason + }DB_PASSWORD is set"
  fi

  if [ "$detected" = "1" ]; then
    echo "[build_params] Auto-detected WITH_RDS=1 ($reason)" >&2
    WITH_RDS=1
  fi
}

build_ros_params() {
  # Run auto-detection before building params
  _auto_detect_rds

  local n=0
  n=$((n+1)); _add_param "$n" AppName            "$APP_NAME"
  n=$((n+1)); _add_param "$n" InstanceType       "$INSTANCE_TYPE"
  n=$((n+1)); _add_param "$n" Password           "$PASSWORD"
  n=$((n+1)); _add_param "$n" SystemDiskSize     "$DISK"
  n=$((n+1)); _add_param "$n" BackendPort        "$PORT"

  # ZoneId: single-node uses ZONE_ID
  if [ -n "${ZONE_ID:-}" ]; then
    n=$((n+1)); _add_param "$n" ZoneId           "$ZONE_ID"
  fi

  if [ "${WITH_RDS:-0}" = "1" ]; then
    # Validate required RDS variable: DB_PASSWORD is the critical one (others have defaults in callers)
    : "${DB_PASSWORD:?WITH_RDS=1 but DB_PASSWORD is not set. Set DB_PASSWORD env var or pass WITH_RDS=1 with DB_PASSWORD.}"
    n=$((n+1)); _add_param "$n" DbInstanceClass   "${DB_INSTANCE_CLASS:-mysql.n2.medium.1}"
    n=$((n+1)); _add_param "$n" DbInstanceStorage "${DB_INSTANCE_STORAGE:-20}"
    n=$((n+1)); _add_param "$n" DbName            "${DB_NAME:-appdb}"
    n=$((n+1)); _add_param "$n" DbAccount         "${DB_ACCOUNT:-appuser}"
    n=$((n+1)); _add_param "$n" DbPassword        "$DB_PASSWORD"
  else
    n=$((n+1)); _add_param "$n" UserDataScript    "${USERDATA:?missing USERDATA}"
  fi
}
