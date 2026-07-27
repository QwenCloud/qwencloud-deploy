#!/usr/bin/env bash
# Detect existing ROS stacks created by this tool (tag from=qwencloud) in the current region.
#
# Purpose:
#   - Detect existing deployment of the same project → offer hot update/redeploy options
#
# Usage:
#   ./check_existing.sh <region> [appName]
#
#   appName  Optional; when provided, distinguishes "same project" vs "other project" stacks.
#
# stdout: JSON object, see Python output at the end of the script
# Exit codes:
#   0  Existing resources found (stdout has content)
#   1  No existing resources
#   2  Query/parse failed
set -uo pipefail

usage() { echo "Usage: $0 <region> [appName]" >&2; exit 64; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
REGION="$1"
APP_NAME="${2:-}"

# --- Query ROS stacks ---
STACKS_OUT=$(aliyun ros ListStacks --RegionId "$REGION" \
  --Tag.1.Key from --Tag.1.Value qwencloud 2>&1) || {
  echo "[existing] ListStacks failed: $STACKS_OUT" >&2; exit 2; }

# --- Analyze ---
python3 - "$APP_NAME" <<'PY' "$STACKS_OUT"
import json, sys

app_name = sys.argv[1]
stacks_raw = sys.argv[2]

try:
    stacks_data = json.loads(stacks_raw)
except Exception as e:
    sys.stderr.write(f"Failed to parse ListStacks: {e}\n"); sys.exit(2)

all_stacks = []
same_app_stacks = []

for s in stacks_data.get("Stacks", []):
    if s.get("Status") == "DELETE_COMPLETE":
        continue
    tags = s.get("Tags", [])
    tag_app_name = ""
    for t in tags:
        key = t.get("Key") or t.get("TagKey") or ""
        val = t.get("Value") or t.get("TagValue") or ""
        if key == "qwencloud-appName":
            tag_app_name = val

    stack_info = {
        "stack_name": s.get("StackName", ""),
        "stack_id": s.get("StackId", ""),
        "status": s.get("Status", ""),
        "create_time": s.get("CreateTime", ""),
        "app_name": tag_app_name,
    }
    all_stacks.append(stack_info)

    if app_name and tag_app_name == app_name:
        same_app_stacks.append(stack_info)

result = {
    "stacks": all_stacks,
    "same_app_stacks": same_app_stacks,
}

if all_stacks:
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0)
else:
    sys.stderr.write("[existing] No existing resources created by this tool found\n")
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(1)
PY
