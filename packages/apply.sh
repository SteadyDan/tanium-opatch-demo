#!/bin/sh
# Package: Oracle OPatch - 3 Apply
# Command: /bin/sh apply.sh 12345678
# Files:   apply.sh, lib.sh
#
# Gate: only runs on endpoints whose state is 'prereq_ok'.
# Sequence inside the step: stop DB -> opatch apply -> start DB -> verify inventory.
# The service is restarted whatever happens after the stop (trap), so a failed
# apply never leaves the instance down.
STEP=apply
. "$(dirname "$0")/lib.sh"

DEST="$STAGE_ROOT/$PATCH_ID"
OUT="$STATE_DIR/last_opatch_output.txt"
log "begin: patch $PATCH_ID, current state $(get_state)"
require_state prereq_ok
[ "$(get_state_patch)" = "$PATCH_ID" ] || fail "$RC_SEQUENCE" "prereq was for patch $(get_state_patch), not $PATCH_ID"
[ -d "$DEST" ] || fail "$RC_MISSING" "staging directory $DEST missing"

restart_needed=0
cleanup() {
  if [ "$restart_needed" -eq 1 ]; then
    svc_start || log "WARNING: $SERVICE did not come back up"
    restart_needed=0
  fi
}
trap cleanup EXIT INT TERM

# 1. quiesce
if svc_is_active; then
  svc_stop || fail "$RC_SERVICE" "could not stop $SERVICE"
  restart_needed=1
else
  log "$SERVICE already stopped"
fi

# 2. patch
log "running opatch apply as $ORACLE_USER"
as_oracle "cd '$DEST' && opatch apply -silent" > "$OUT" 2>&1
rc=$?
cat "$OUT"; cat "$OUT" >> "$LOG_FILE"
log "opatch apply exit code: $rc"

# 3. restart (also happens via trap on any exit path)
cleanup
trap - EXIT INT TERM
svc_is_active || fail "$RC_SERVICE" "$SERVICE failed to restart after patching"

[ "$rc" -eq 0 ] || fail "$rc" "opatch apply returned $rc"

# 4. verify against the inventory, not the exit code alone
if as_oracle "opatch lsinventory" 2>/dev/null | grep -q "^Patch  $PATCH_ID "; then
  log "verified: patch $PATCH_ID present in lsinventory"
  set_state applied 0
  exit 0
fi
fail "$RC_VERIFY" "opatch reported success but $PATCH_ID is not in lsinventory"
