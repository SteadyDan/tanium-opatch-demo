#!/bin/sh
# Solaris 10: /bin/sh is the 1989 Bourne shell (no $(...), grep has no -q, id
# has no -un). Re-exec under the XPG4 POSIX shell with XPG4 tools first on
# PATH before any modern syntax is parsed. Absent on Linux, so a no-op there.
if [ -z "$EPX_POSIX" ] && [ -x /usr/xpg4/bin/sh ]; then
  EPX_POSIX=1; export EPX_POSIX
  PATH=/usr/xpg4/bin:$PATH; export PATH
  exec /usr/xpg4/bin/sh "$0" ${1+"$@"}
fi
# Package: Oracle OPatch - 1 Stage
# Command: /bin/sh stage.sh 12345678
# Files:   stage.sh, lib.sh (local)
#          p12345678_190000_Linux-x86-64.zip          (REMOTE - URL)
#          p12345678_190000_Linux-x86-64.zip.sha256   (REMOTE - URL)
#
# The Tanium Server pulls the two remote files, the client receives them via
# the peer cache and runs this script with the package directory as cwd.
# Nothing in here reaches out to the network itself.
STEP=stage
. "$(dirname "$0")/lib.sh"

# Accept any platform suffix: p<id>_<release>_<Linux-x86-64|SOLARIS64|...>.zip
ZIP=""
for f in "p${PATCH_ID}_"*.zip; do [ -f "$f" ] && { ZIP="$f"; break; }; done
[ -n "$ZIP" ] || ZIP="p${PATCH_ID}_190000_Linux-x86-64.zip"
DEST="$STAGE_ROOT/$PATCH_ID"

log "begin: patch $PATCH_ID, cwd $(pwd), current state $(get_state)"

# Staging is safe to re-run from any state except mid-flight ones.
require_state none staged prereq_ok applied rolled_back failed

[ -f "$ZIP" ]        || fail "$RC_MISSING" "$ZIP not delivered with the package"
[ -f "$ZIP.sha256" ] || fail "$RC_MISSING" "$ZIP.sha256 not delivered with the package"

expected=$(cut -d' ' -f1 "$ZIP.sha256")
actual=$(sha256_of "$ZIP")
log "sha256 expected=$expected"
log "sha256 actual  =$actual"
[ "$expected" = "$actual" ] || fail "$RC_CHECKSUM" "checksum mismatch on $ZIP"

have unzip || fail "$RC_MISSING" "unzip not installed"
mkdir -p "$STAGE_ROOT"
rm -rf "$DEST"
unzip -q -o "$ZIP" -d "$STAGE_ROOT" || fail 1 "unzip failed"
[ -f "$DEST/etc/config/inventory.xml" ] || fail "$RC_VERIFY" "archive did not contain $PATCH_ID/etc/config/inventory.xml"
rm -f "$DEST/FORCE_CONFLICT"
chown -R "$ORACLE_USER" "$DEST"
log "staged to $DEST ($(du -sk "$DEST" | cut -f1) KB)"

set_state staged 0
exit 0
