#!/bin/sh
# Sensor: Oracle Patch State
# Returns one pipe-delimited row: state|patch_id|last_exit_code|last_updated
# Written atomically by lib.sh so the sensor never sees a partial line.
f=/var/opt/oracle_patch/state
if [ -r "$f" ] && [ -s "$f" ]; then
  head -n 1 "$f"
else
  echo "not_configured|0|0|never"
fi
