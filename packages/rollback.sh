#!/bin/sh
# Solaris 10: /bin/sh is the 1989 Bourne shell (no $(...), grep has no -q, id
# has no -un). Re-exec under the XPG4 POSIX shell with XPG4 tools first on
# PATH before any modern syntax is parsed. Absent on Linux, so a no-op there.
if [ -z "$EPX_POSIX" ] && [ -x /usr/xpg4/bin/sh ]; then
  EPX_POSIX=1; export EPX_POSIX
  PATH=/usr/xpg4/bin:$PATH; export PATH
  exec /usr/xpg4/bin/sh "$0" ${1+"$@"}
fi
# Package: Oracle OPatch - 4 Rollback
# Command: /bin/sh rollback.sh 12345678
# Files:   rollback.sh, lib.sh
#
# Gate: runs on endpoints in 'applied' (planned rollback) or 'failed'
# (remediation branch from the playbook). If the patch is not actually in the
# inventory there is nothing to roll back, and the step reports that honestly.
STEP=rollback
. "$(dirname "$0")/lib.sh"

OUT="$STATE_DIR/last_opatch_output.txt"
log "begin: patch $PATCH_ID, current state $(get_state)"
require_state applied failed

if ! as_oracle "opatch lsinventory" 2>/dev/null | grep -q "^Patch  $PATCH_ID "; then
  log "patch $PATCH_ID is not in the inventory; nothing to roll back"
  set_state rolled_back 0
  exit 0
fi

restart_needed=0
cleanup() {
  if [ "$restart_needed" -eq 1 ]; then
    svc_start || log "WARNING: $SERVICE did not come back up"
    restart_needed=0
  fi
}
trap cleanup EXIT INT TERM

if svc_is_active; then
  svc_stop || fail "$RC_SERVICE" "could not stop $SERVICE"
  restart_needed=1
fi

log "running opatch rollback as $ORACLE_USER"
as_oracle "opatch rollback -id $PATCH_ID -silent" > "$OUT" 2>&1
rc=$?
cat "$OUT"; cat "$OUT" >> "$LOG_FILE"
log "opatch rollback exit code: $rc"

cleanup
trap - EXIT INT TERM
svc_is_active || fail "$RC_SERVICE" "$SERVICE failed to restart after rollback"
[ "$rc" -eq 0 ] || fail "$rc" "opatch rollback returned $rc"

if as_oracle "opatch lsinventory" 2>/dev/null | grep -q "^Patch  $PATCH_ID "; then
  fail "$RC_VERIFY" "opatch reported success but $PATCH_ID is still in lsinventory"
fi
log "verified: patch $PATCH_ID removed"
set_state rolled_back 0
exit 0
