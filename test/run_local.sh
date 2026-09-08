#!/bin/sh
# End-to-end test of the chain on a throwaway Linux box or container.
# Runs every script under dash (Ubuntu's /bin/sh) so bashisms fail loudly.
# Needs root, unzip, zip, sha256sum. Works without systemd (pidfile fallback).
#
#   sudo sh test/run_local.sh
set -u
KIT=$(cd "$(dirname "$0")/.." && pwd)
SH=${SH:-dash}
STATE=/var/opt/oracle_patch/state
PASS=0; FAILN=0

expect_state() {  # expect_state <state> <rc> <label>
  got=$(cut -d'|' -f1,3 "$STATE")
  if [ "$got" = "$1|$2" ]; then PASS=$((PASS+1)); echo "  PASS  $3 -> $got"
  else FAILN=$((FAILN+1)); echo "  FAIL  $3 -> got '$got', wanted '$1|$2'"; fi
}
expect_rc() {     # expect_rc <want> <got> <label>
  if [ "$1" = "$2" ]; then PASS=$((PASS+1)); echo "  PASS  $3 exit $2"
  else FAILN=$((FAILN+1)); echo "  FAIL  $3 exit $2, wanted $1"; fi
}

echo "== 0. endpoint prep"
$SH "$KIT/endpoint/prep_endpoint.sh" >/dev/null 2>&1 || { echo "prep failed"; exit 1; }
# no systemd in most containers: bring the simulated DB up via the pidfile path
( STEP=test; . "$KIT/packages/lib.sh"; svc_is_active || svc_start ) >/dev/null
echo "  service mode: $( . "$KIT/packages/lib.sh" >/dev/null; svc_mode )"

echo "== 1. build payload and fake Tanium action directory"
$SH "$KIT/patch/build_patch_zip.sh" 12345678 >/dev/null
ACT=$(mktemp -d /tmp/Action_XXXX)
cp "$KIT/packages/"*.sh "$KIT/patch/dist/"p12345678_* "$ACT"/
cd "$ACT" || exit 1

echo "== 2. sequence violation: apply before stage"
$SH apply.sh 12345678 >/dev/null 2>&1; rc=$?
expect_rc 90 $rc "apply out of order"
expect_state none 0 "state untouched by violation"

echo "== 3. happy path"
$SH stage.sh 12345678 >/dev/null 2>&1;    expect_rc 0 $? "stage";    expect_state staged 0 "after stage"
$SH prereq.sh 12345678 >/dev/null 2>&1;   expect_rc 0 $? "prereq";   expect_state prereq_ok 0 "after prereq"
$SH apply.sh 12345678 >/dev/null 2>&1;    expect_rc 0 $? "apply";    expect_state applied 0 "after apply"
su - oracle -c "opatch lsinventory" | grep -q "^Patch  12345678 " && { PASS=$((PASS+1)); echo "  PASS  patch in lsinventory"; } || { FAILN=$((FAILN+1)); echo "  FAIL  patch not in lsinventory"; }
( . "$KIT/packages/lib.sh" >/dev/null; svc_is_active ) && { PASS=$((PASS+1)); echo "  PASS  DB service back up"; } || { FAILN=$((FAILN+1)); echo "  FAIL  DB service down after apply"; }

echo "== 4. idempotency: re-run apply after applied (should be refused as out of sequence)"
$SH apply.sh 12345678 >/dev/null 2>&1; expect_rc 90 $? "apply twice"; expect_state applied 0 "state kept"

echo "== 5. rollback"
$SH rollback.sh 12345678 >/dev/null 2>&1; expect_rc 0 $? "rollback"; expect_state rolled_back 0 "after rollback"
su - oracle -c "opatch lsinventory" | grep -q "^Patch  12345678 " && { FAILN=$((FAILN+1)); echo "  FAIL  patch still in inventory"; } || { PASS=$((PASS+1)); echo "  PASS  inventory clean"; }

echo "== 6. conflict branch (FORCE_CONFLICT)"
$SH stage.sh 12345678 >/dev/null 2>&1;    expect_state staged 0 "re-stage"
touch /u01/stage/12345678/FORCE_CONFLICT
$SH prereq.sh 12345678 >/dev/null 2>&1;   expect_rc 73 $? "prereq with conflict"; expect_state failed 73 "after conflict"
$SH apply.sh 12345678 >/dev/null 2>&1;    expect_rc 90 $? "apply blocked after failure"
$SH rollback.sh 12345678 >/dev/null 2>&1; expect_rc 0 $? "rollback from failed (nothing applied)"; expect_state rolled_back 0 "after remediation"
rm -f /u01/stage/12345678/FORCE_CONFLICT

echo "== 7. tampered payload"
$SH stage.sh 12345678 >/dev/null 2>&1
printf 'x' >> "$ACT/p12345678_190000_Linux-x86-64.zip"
$SH stage.sh 12345678 >/dev/null 2>&1; expect_rc 92 $? "stage with bad checksum"; expect_state failed 92 "after checksum failure"

echo "== 8. sensor output"
$SH "$KIT/sensor/oracle_patch_state.sh"

echo
echo "passed=$PASS failed=$FAILN"
[ "$FAILN" -eq 0 ]
