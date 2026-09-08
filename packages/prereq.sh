#!/bin/sh
# Package: Oracle OPatch - 2 Prereq
# Command: /bin/sh prereq.sh 12345678
# Files:   prereq.sh, lib.sh
#
# Gate: only runs on endpoints whose state is 'staged'.
# Outcome: prereq_ok (rc 0) or failed (rc 73 conflict / other).
STEP=prereq
. "$(dirname "$0")/lib.sh"

DEST="$STAGE_ROOT/$PATCH_ID"
OUT="$STATE_DIR/last_opatch_output.txt"
log "begin: patch $PATCH_ID, current state $(get_state)"
require_state staged

[ "$(get_state_patch)" = "$PATCH_ID" ] || fail "$RC_SEQUENCE" "staged patch $(get_state_patch) does not match requested $PATCH_ID"
[ -d "$DEST" ] || fail "$RC_MISSING" "staging directory $DEST missing"

log "running OPatch conflict check as $ORACLE_USER"
# Capture to a file rather than piping through tee: a pipe would hide opatch's exit code.
as_oracle "cd '$DEST' && opatch prereq CheckConflictAgainstOHWithDetail -ph ./" > "$OUT" 2>&1
rc=$?
cat "$OUT"; cat "$OUT" >> "$LOG_FILE"
log "opatch prereq exit code: $rc"

[ "$rc" -eq 0 ] || fail "$rc" "OPatch prereq check returned $rc (73 = conflict)"
set_state prereq_ok 0
exit 0
