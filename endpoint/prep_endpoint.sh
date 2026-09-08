#!/bin/sh
# ---------------------------------------------------------------------------
# prep_endpoint.sh — one-time lab setup on an Ubuntu endpoint.
# Run as root (sudo). Can also be pushed as a Tanium package with the two
# sibling files (opatch, oracle-db-sim.service) attached.
#
# Creates:
#   oracle user + oinstall group
#   ORACLE_HOME with the stub opatch and an empty interim-patch inventory
#   /u01/stage for patch staging, /var/opt/oracle_patch for orchestrator state
#   oracle-db-sim.service (dummy DB instance, running)
# ---------------------------------------------------------------------------
set -u

ORACLE_HOME=/u01/app/oracle/product/19/dbhome_1
STAGE_ROOT=/u01/stage
STATE_DIR=/var/opt/oracle_patch
HERE=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

echo "[prep] users and groups"
getent group oinstall >/dev/null || groupadd oinstall
getent passwd oracle  >/dev/null || useradd -m -g oinstall -s /bin/sh -c "Oracle software owner (lab)" oracle

echo "[prep] directories"
mkdir -p "$ORACLE_HOME/OPatch" "$ORACLE_HOME/inventory" "$ORACLE_HOME/cfgtoollogs/opatch" \
         "$ORACLE_HOME/bin" "$STAGE_ROOT" "$STATE_DIR"
: > "$ORACLE_HOME/inventory/interim_patches.txt"
touch "$ORACLE_HOME/bin/oracle"
chown -R oracle:oinstall /u01
chmod 755 "$STATE_DIR"

echo "[prep] stub opatch"
install -o oracle -g oinstall -m 755 "$HERE/opatch" "$ORACLE_HOME/OPatch/opatch"

# Give the oracle login shell a usable environment (mirrors a real Oracle box)
PROFILE=/home/oracle/.profile
grep -q ORACLE_HOME "$PROFILE" 2>/dev/null || cat >> "$PROFILE" <<EOF
export ORACLE_HOME=$ORACLE_HOME
export PATH=\$PATH:\$ORACLE_HOME/bin:\$ORACLE_HOME/OPatch
EOF
chown oracle:oinstall "$PROFILE"

echo "[prep] dummy database service"
if [ -d /run/systemd/system ]; then
  install -m 644 "$HERE/oracle-db-sim.service" /etc/systemd/system/oracle-db-sim.service
  systemctl daemon-reload
  systemctl enable --now oracle-db-sim.service
  systemctl is-active oracle-db-sim.service
else
  echo "[prep] systemd not running here; skipping service install"
fi

echo "[prep] initial orchestrator state"
[ -f "$STATE_DIR/state" ] || printf 'none|0|0|%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE_DIR/state"

echo "[prep] smoke test as oracle"
su - oracle -c "opatch version" && su - oracle -c "opatch lsinventory" | grep 'Interim patches'
echo "[prep] done"
