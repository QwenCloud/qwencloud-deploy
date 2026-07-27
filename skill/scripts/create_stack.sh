#!/usr/bin/env bash
# Create ROS stack. Tags: from=qwencloud / qwencloud-appName / qwencloud-appDesc; auto-rollback on failure (DisableRollback=false).
# Full-stack pay-as-you-go (PostPaid).
# Required env vars: APP_NAME, INSTANCE_TYPE, PASSWORD, USERDATA_FILE
# Required env vars (cont.): APP_DESC (application description)
# Optional: SYSTEM_DISK_SIZE=40, BACKEND_PORT=8080, TIMEOUT_MIN=30 (default 60 with RDS)
# With RDS (WITH_RDS=1):
#   Required: DB_PASSWORD
#   Optional: DB_INSTANCE_CLASS=mysql.n2.medium.1, DB_INSTANCE_STORAGE=20,
#             DB_NAME=appdb, DB_ACCOUNT=appuser
#   Note: RDS templates have UserData inlined; it's not passed as a Parameter; USERDATA_FILE is for debug reference only
# Note: WITH_RDS is auto-detected from template URL (contains "_rds") or DB_PASSWORD env var.
#       Explicit WITH_RDS=1 always takes precedence.
# Usage:
#   ./create_stack.sh <region> <template-url> <stack-name>
# stdout: StackId only (one line)
set -uo pipefail

usage() {
  echo "Usage: APP_NAME=... APP_DESC=... INSTANCE_TYPE=... PASSWORD=... USERDATA_FILE=... $0 <region> <template-url> <stack-name>" >&2
  exit 64
}
[ $# -eq 3 ] || usage
REGION="$1"; TPL_URL="$2"; NAME="$3"
: "${APP_NAME:?missing APP_NAME}"
: "${INSTANCE_TYPE:?missing INSTANCE_TYPE}"
: "${PASSWORD:?missing PASSWORD}"
: "${USERDATA_FILE:?missing USERDATA_FILE}"
[ -f "$USERDATA_FILE" ] || { echo "USERDATA_FILE not found: $USERDATA_FILE" >&2; exit 1; }
: "${APP_DESC:?missing APP_DESC}"
DISK="${SYSTEM_DISK_SIZE:-40}"
PORT="${BACKEND_PORT:-8080}"
PROJECT_ROOT="${PROJECT_ROOT:-.}"   # Write temporary state file to this directory (defaults to current project root)

# Export TPL_URL so _build_params.sh can auto-detect RDS from template filename
export TPL_URL

WITH_RDS="${WITH_RDS:-0}"
if [ "$WITH_RDS" = "1" ]; then
  : "${DB_PASSWORD:?missing DB_PASSWORD (WITH_RDS=1)}"
fi

# Pre-fill RDS defaults (harmless if WITH_RDS=0; required if auto-detected later by _build_params.sh).
# DB_PASSWORD must be set by caller when RDS is intended; _build_params.sh validates.
DB_INSTANCE_CLASS="${DB_INSTANCE_CLASS:-mysql.n2.medium.1}"
DB_INSTANCE_STORAGE="${DB_INSTANCE_STORAGE:-20}"
DB_NAME="${DB_NAME:-appdb}"
DB_ACCOUNT="${DB_ACCOUNT:-appuser}"

# Timeout: RDS creation takes longer
if [ "${WITH_RDS:-0}" = "1" ]; then
  TIMEOUT="${TIMEOUT_MIN:-60}"
else
  # May be updated after auto-detection in build_ros_params
  TIMEOUT="${TIMEOUT_MIN:-30}"
fi

USERDATA="$(cat "$USERDATA_FILE")"

# Build parameter array dynamically (shared logic)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/build_params.sh"
build_ros_params

# After auto-detection, re-check timeout (auto-detection may have set WITH_RDS=1)
if [ "${WITH_RDS:-0}" = "1" ] && [ "${TIMEOUT_MIN:-}" = "" ] && [ "$TIMEOUT" = "30" ]; then
  TIMEOUT=60
  echo "[create] Adjusted timeout to 60m for RDS (auto-detected)" >&2
fi

# ─── Retry-safe: check if stack with same name already exists ───────────────
# If a previous attempt timed out at the CLI layer but the server-side CreateStack
# actually succeeded, we must detect and reuse that stack rather than creating a
# duplicate (which would leak resources).
EXISTING_SID=""
echo "[create] Checking for existing stack with name: $NAME" >&2
EXISTING=$(aliyun ros ListStacks \
  --RegionId "$REGION" \
  --StackName.1 "$NAME" \
  --Status.1 CREATE_IN_PROGRESS \
  --Status.2 CREATE_COMPLETE \
  --Status.3 CREATE_FAILED \
  --PageSize 1 2>&1) || true

EXISTING_SID=$(echo "$EXISTING" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    stacks = d.get('Stacks', [])
    if stacks:
        s = stacks[0]
        status = s.get('Status', '')
        sid = s.get('StackId', '')
        if status in ('CREATE_IN_PROGRESS', 'CREATE_COMPLETE'):
            print(sid)
        elif status == 'CREATE_FAILED':
            # Failed stack exists with same name — print empty so we can handle it
            sys.stderr.write(f'[create] Found failed stack {sid} with same name, will delete and recreate\n')
except:
    pass
" 2>/dev/null)

if [ -n "$EXISTING_SID" ]; then
  echo "[create] Found existing stack $EXISTING_SID with name $NAME — reusing (no duplicate creation)" >&2
  STACK_ID="$EXISTING_SID"
else
  # If a CREATE_FAILED stack with the same name exists, delete it first to free the name
  FAILED_SID=$(echo "$EXISTING" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    stacks = d.get('Stacks', [])
    if stacks and stacks[0].get('Status') == 'CREATE_FAILED':
        print(stacks[0].get('StackId', ''))
except:
    pass
" 2>/dev/null)
  if [ -n "$FAILED_SID" ]; then
    echo "[create] Deleting previously failed stack $FAILED_SID to free name..." >&2
    aliyun ros DeleteStack --RegionId "$REGION" --StackId "$FAILED_SID" >/dev/null 2>&1 || true
    # Brief wait for deletion to register
    sleep 5
  fi

  # Create new stack
  OUT=$(aliyun ros CreateStack \
    --RegionId "$REGION" \
    --StackName "$NAME" \
    --TemplateURL "$TPL_URL" \
    --DisableRollback false \
    --TimeoutInMinutes "$TIMEOUT" \
    --Tags.1.Key from                --Tags.1.Value qwencloud \
    --Tags.2.Key qwencloud-appName  --Tags.2.Value "$APP_NAME" \
    --Tags.3.Key qwencloud-appDesc  --Tags.3.Value "$APP_DESC" \
    "${PARAMS[@]}" 2>&1)
  CODE=$?
  if [ $CODE -ne 0 ]; then
    # CLI timeout: server may have accepted the request. Query by name as fallback.
    echo "[create] CreateStack CLI returned error (code=$CODE), checking if stack was created server-side..." >&2
    sleep 3
    FALLBACK=$(aliyun ros ListStacks \
      --RegionId "$REGION" \
      --StackName.1 "$NAME" \
      --Status.1 CREATE_IN_PROGRESS \
      --Status.2 CREATE_COMPLETE \
      --PageSize 1 2>&1) || true
    STACK_ID=$(echo "$FALLBACK" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    stacks = d.get('Stacks', [])
    if stacks:
        print(stacks[0].get('StackId', ''))
except:
    pass
" 2>/dev/null)
    if [ -n "$STACK_ID" ]; then
      echo "[create] Stack was created server-side despite CLI error: $STACK_ID" >&2
    else
      echo "$OUT" >&2
      exit $CODE
    fi
  else
    STACK_ID=$(echo "$OUT" | python3 -c "import json,sys
try: print(json.load(sys.stdin)['StackId'])
except Exception: pass")
    [ -z "$STACK_ID" ] && { echo "Cannot parse StackId (CreateStack returned unexpected content)" >&2; echo "$OUT" >&2; exit 1; }
  fi
fi

# Write a temporary state file immediately after getting StackId: even if the wait-for-final-state
# phase is interrupted (terminal closed / network lost), delete_stack.sh can still clean up,
# preventing orphaned stacks that keep billing. record_state.py will overwrite with full state on success.
DB_ENGINE_HINT=""
[ "$WITH_RDS" = "1" ] && DB_ENGINE_HINT="mysql"
python3 - "$PROJECT_ROOT" "$STACK_ID" "$NAME" "$REGION" "$DB_ENGINE_HINT" <<'PY' || true
import datetime, json, os, sys
root, sid, name, region, db = sys.argv[1:6]
state = {
    "version": 1,
    "stack_id": sid,
    "stack_name": name,
    "region_id": region,
    "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
    "tags": [{"Key": "from", "Value": "qwencloud"}, {"Key": "qwencloud-appName", "Value": os.environ.get("APP_NAME", "")}, {"Key": "qwencloud-appDesc", "Value": os.environ.get("APP_DESC", "")}],
    "provisional": True,
    "notes": "CreateStack submitted, waiting for final state; record_state.py will overwrite with full state on success.",
}
if db:
    state["db_engine"] = db
path = os.path.join(root, ".qwencloud-deploy")
with open(path, "w", encoding="utf-8") as f:
    json.dump(state, f, ensure_ascii=False, indent=2)
sys.stderr.write(f"[create] Wrote temporary state file {path} (contains stack_id, cleanup possible even if interrupted)\n")
PY

echo "$STACK_ID"
