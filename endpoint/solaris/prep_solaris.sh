#!/bin/sh
# Solaris 10: /bin/sh is the 1989 Bourne shell (no $(...), grep has no -q, id
# has no -un). Re-exec under the XPG4 POSIX shell with XPG4 tools first on
# PATH before any modern syntax is parsed. Absent on Linux, so a no-op there.
if [ -z "$EPX_POSIX" ] && [ -x /usr/xpg4/bin/sh ]; then
  EPX_POSIX=1; export EPX_POSIX
  PATH=/usr/xpg4/bin:$PATH; export PATH
  exec /usr/xpg4/bin/sh "$0" ${1+"$@"}
fi
have() { type "$1" >/dev/null 2>&1; }
# ---------------------------------------------------------------------------
# prep_solaris.sh — one-time lab setup on a Solaris 11 endpoint.
# Run as root. Same outcome as prep_endpoint.sh on Ubuntu:
#   oracle user + oinstall group
#   ORACLE_HOME with the stub opatch and an empty interim-patch inventory
#   /u01/stage for patch staging, /var/opt/oracle_patch for orchestrator state
#   svc:/application/oracle-db-sim (dummy DB instance, online)
#
# Expects opatch, oracle-db-sim.xml and oracle-db-sim (method) alongside it.
# Works on Solaris 10 and 11: the shim at the top re-execs under /usr/xpg4/bin/sh.
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
if ! have unzip; then
  if [ -x /usr/bin/pkg ]; then pkg install -q unzip; else echo "[prep] WARNING: unzip missing (Solaris 10: pkgadd SUNWunzip)"; fi
fi

echo "[prep] users and groups"
getent group oinstall >/dev/null || groupadd oinstall
if ! getent passwd oracle >/dev/null; then
  # Solaris useradd needs an explicit home with -m
  ORA_SHELL=/bin/sh; [ -x /usr/xpg4/bin/sh ] && ORA_SHELL=/usr/xpg4/bin/sh
  useradd -m -d /export/home/oracle -g oinstall -s "$ORA_SHELL" -c "Oracle software owner (lab)" oracle
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
ORACLE_HOME=$ORACLE_HOME; export ORACLE_HOME
PATH=\$PATH:\$ORACLE_HOME/bin:\$ORACLE_HOME/OPatch; export PATH
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
