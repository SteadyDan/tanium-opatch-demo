#!/bin/sh
# ---------------------------------------------------------------------------
# prep_solaris.sh — one-time lab setup on a Solaris 11 endpoint.
# Run as root. Same outcome as prep_endpoint.sh on Ubuntu:
#   oracle user + oinstall group
#   ORACLE_HOME with the stub opatch and an empty interim-patch inventory
#   /u01/stage for patch staging, /var/opt/oracle_patch for orchestrator state
#   svc:/application/oracle-db-sim (dummy DB instance, online)
#
# Expects opatch, oracle-db-sim.xml and oracle-db-sim (method) alongside it.
# Solaris 11 /bin/sh is ksh93, so $(...) and $((...)) are fine. On Solaris 10
# run the package commands with /usr/xpg4/bin/sh instead of /bin/sh.
# ---------------------------------------------------------------------------
set -u

ORACLE_HOME=/u01/app/oracle/product/19/dbhome_1
STAGE_ROOT=/u01/stage
STATE_DIR=/var/opt/oracle_patch
HERE=$(cd "$(dirname "$0")" && pwd)
# The stub lives one level up in the kit; alongside when shipped as a package.
[ -f "$HERE/opatch" ] && STUB="$HERE/opatch" || STUB="$HERE/../opatch"

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }
[ -f "$STUB" ] || { echo "stub opatch not found next to this script"; exit 1; }

echo "[prep] tools"
command -v unzip >/dev/null 2>&1 || pkg install -q unzip || echo "[prep] WARNING: unzip missing; pkg install unzip"

echo "[prep] users and groups"
getent group oinstall >/dev/null || groupadd oinstall
if ! getent passwd oracle >/dev/null; then
  # Solaris useradd needs an explicit home with -m
  useradd -m -d /export/home/oracle -g oinstall -s /bin/sh -c "Oracle software owner (lab)" oracle
fi
ORA_HOME_DIR=$(getent passwd oracle | cut -d: -f6)

echo "[prep] directories"
mkdir -p "$ORACLE_HOME/OPatch" "$ORACLE_HOME/inventory" "$ORACLE_HOME/cfgtoollogs/opatch" \
         "$ORACLE_HOME/bin" "$STAGE_ROOT" "$STATE_DIR"
: > "$ORACLE_HOME/inventory/interim_patches.txt"
touch "$ORACLE_HOME/bin/oracle"
chown -R oracle:oinstall /u01
chmod 755 "$STATE_DIR"

echo "[prep] stub opatch"
cp "$STUB" "$ORACLE_HOME/OPatch/opatch"
chown oracle:oinstall "$ORACLE_HOME/OPatch/opatch"
chmod 755 "$ORACLE_HOME/OPatch/opatch"

PROFILE="$ORA_HOME_DIR/.profile"
grep -q ORACLE_HOME "$PROFILE" 2>/dev/null || cat >> "$PROFILE" <<EOF
export ORACLE_HOME=$ORACLE_HOME
export PATH=\$PATH:\$ORACLE_HOME/bin:\$ORACLE_HOME/OPatch
EOF
chown oracle:oinstall "$PROFILE"

echo "[prep] dummy database service (SMF)"
cp "$HERE/oracle-db-sim" /lib/svc/method/oracle-db-sim
chmod 755 /lib/svc/method/oracle-db-sim
cp "$HERE/oracle-db-sim.xml" /var/svc/manifest/application/oracle-db-sim.xml
svccfg import /var/svc/manifest/application/oracle-db-sim.xml
svcadm enable -s oracle-db-sim
svcs oracle-db-sim

echo "[prep] initial orchestrator state"
[ -f "$STATE_DIR/state" ] || printf 'none|0|0|%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_DIR/state"

echo "[prep] smoke test as oracle"
su - oracle -c "opatch version" && su - oracle -c "opatch lsinventory" | grep 'Interim patches'
echo "[prep] done"
