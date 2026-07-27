#!/usr/bin/env bash
# Poll GetStack until terminal state.
# Usage: ./wait_stack.sh <region> <stack-id> [interval=10] [max-min=40]
# Terminal states: CREATE_COMPLETE | CREATE_FAILED | ROLLBACK_COMPLETE | ROLLBACK_FAILED | DELETE_FAILED
# stdout: Final GetStack full JSON
# Exit codes: 0 = CREATE_COMPLETE; 2 = any *FAILED / ROLLBACK; 3 = timeout
set -uo pipefail

usage() { echo "Usage: $0 <region> <stack-id> [interval=10] [max-min=40]" >&2; exit 64; }
[ $# -ge 2 ] || usage
REGION="$1"; SID="$2"; INTERVAL="${3:-10}"; MAX_MIN="${4:-40}"

DEADLINE=$(( $(date +%s) + MAX_MIN * 60 ))
LAST=""
TERMINAL_OK="CREATE_COMPLETE UPDATE_COMPLETE"
TERMINAL_BAD="CREATE_FAILED CREATE_ROLLBACK_COMPLETE CREATE_ROLLBACK_FAILED ROLLBACK_COMPLETE ROLLBACK_FAILED DELETE_FAILED"

while :; do
  if [ $(date +%s) -gt $DEADLINE ]; then
    echo "[wait] Timed out ${MAX_MIN}m" >&2
    [ -n "$LAST" ] && echo "$LAST"
    exit 3
  fi
  OUT=$(aliyun ros GetStack --RegionId "$REGION" --StackId "$SID" 2>&1)
  CODE=$?
  if [ $CODE -ne 0 ]; then
    if echo "$OUT" | grep -qiE 'StackNotFound|404'; then
      echo "[wait] Stack no longer exists (DELETE_COMPLETE)" >&2
      exit 0
    fi
    echo "[wait] GetStack failed: $OUT" >&2
    sleep "$INTERVAL"; continue
  fi
  LAST="$OUT"
  STATUS=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('Status',''))")
  REASON=$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('StatusReason',''))")
  echo "[wait] $(date -u +%H:%M:%S) Status=$STATUS  Reason=$REASON" >&2

  for ok in $TERMINAL_OK; do
    if [ "$STATUS" = "$ok" ]; then
      echo "$OUT"
      exit 0
    fi
  done
  for bad in $TERMINAL_BAD; do
    if [ "$STATUS" = "$bad" ]; then
      echo "$OUT"
      exit 2
    fi
  done
  sleep "$INTERVAL"
done
