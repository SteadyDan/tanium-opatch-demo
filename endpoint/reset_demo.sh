#!/bin/sh
# reset_demo.sh — put the endpoint back to a clean 'none' state between demo runs.
# Run as root. Keeps the oracle user, ORACLE_HOME and stub opatch; clears
# patch inventory, staging, orchestrator state/logs and any conflict marker,
# and makes sure the simulated DB service is running.
set -u
ORACLE_HOME=/u01/app/oracle/product/19/dbhome_1
[ "$(id -u)" -eq 0 ] || { echo "run as root"; exit 1; }

: > "$ORACLE_HOME/inventory/interim_patches.txt"
rm -rf /u01/stage/* "$ORACLE_HOME/FORCE_CONFLICT" "$ORACLE_HOME"/cfgtoollogs/opatch/*.log
mkdir -p /var/opt/oracle_patch
rm -f /var/opt/oracle_patch/orchestrator.log /var/opt/oracle_patch/last_opatch_output.txt
printf 'none|0|0|%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /var/opt/oracle_patch/state
chown -R oracle:oinstall /u01

if [ -d /run/systemd/system ]; then
  systemctl start oracle-db-sim.service
  systemctl is-active oracle-db-sim.service
fi
echo "state: $(cat /var/opt/oracle_patch/state)"
echo "inventory entries: $(grep -c . "$ORACLE_HOME/inventory/interim_patches.txt" || true)"
