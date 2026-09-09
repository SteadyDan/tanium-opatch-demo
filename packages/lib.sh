#!/bin/sh
# ---------------------------------------------------------------------------
# lib.sh — shared functions for the Oracle OPatch orchestration packages.
# Sourced by stage.sh / prereq.sh / apply.sh / rollback.sh.
#
# Strict POSIX sh. Runs as root under the Tanium Client; hops to the oracle
# user for anything that touches OPatch. Portable to Solaris: service control
# and checksum functions pick systemd / SMF / pidfile and sha256sum / digest
# at runtime.
#
# State file (read by the "Oracle Patch State" sensor):
#   <state>|<patch id>|<last exit code>|<UTC timestamp>
# States: none, staged, prereq_ok, applied, rolled_back, failed
# ---------------------------------------------------------------------------

PATCH_ID="${1:-${PATCH_ID:-12345678}}"
ORACLE_USER="${ORACLE_USER:-oracle}"
ORACLE_HOME="${ORACLE_HOME:-/u01/app/oracle/product/19/dbhome_1}"
STAGE_ROOT="${STAGE_ROOT:-/u01/stage}"
STATE_DIR="${STATE_DIR:-/var/opt/oracle_patch}"
STATE_FILE="$STATE_DIR/state"
LOG_FILE="$STATE_DIR/orchestrator.log"
# Default service name follows the platform: systemd unit on Linux, SMF
# service on Solaris (svc:/application/oracle-db-sim:default). Override with
# ORACLE_SERVICE for a real database service.
if [ -n "${ORACLE_SERVICE:-}" ]; then SERVICE="$ORACLE_SERVICE"
elif command -v svcadm >/dev/null 2>&1 && [ ! -d /run/systemd/system ]; then SERVICE="oracle-db-sim"
else SERVICE="oracle-db-sim.service"; fi
STEP="${STEP:-lib}"

# Exit codes owned by the orchestrator (distinct from OPatch's 0/1/73)
RC_SEQUENCE=90    # step ran out of order
RC_MISSING=91     # expected file not delivered
RC_CHECKSUM=92    # payload failed verification
RC_SERVICE=93     # could not stop/start the database service
RC_VERIFY=94      # post-step verification failed

mkdir -p "$STATE_DIR" 2>/dev/null

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

log() {
  printf '%s [%s] %s\n' "$(now)" "$STEP" "$*"
  printf '%s [%s] %s\n' "$(now)" "$STEP" "$*" >> "$LOG_FILE" 2>/dev/null
}

set_state() {
  # set_state <state> <exit code>  — atomic write so the sensor never reads a half line
  printf '%s|%s|%s|%s\n' "$1" "$PATCH_ID" "$2" "$(now)" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
  log "state -> $1 (rc=$2)"
}

get_state() { cut -d'|' -f1 "$STATE_FILE" 2>/dev/null || echo none; }
get_state_patch() { cut -d'|' -f2 "$STATE_FILE" 2>/dev/null || echo 0; }

require_state() {
  # require_state <allowed> [<allowed> ...] — refuse to run out of sequence.
  # Deliberately does NOT change state: an out-of-order action is a targeting
  # mistake, not a patch failure, and must not mask what the endpoint is in.
  cur=$(get_state)
  for want in "$@"; do
    [ "$cur" = "$want" ] && return 0
  done
  log "SEQUENCE VIOLATION: endpoint is in state '$cur', this step needs one of: $*"
  exit "$RC_SEQUENCE"
}

fail() {
  # fail <exit code> <message>
  rc="$1"; shift
  log "FAILED: $*"
  set_state failed "$rc"
  exit "$rc"
}

as_oracle() {
  # Run a command as the Oracle software owner with ORACLE_HOME and OPatch on PATH.
  # `su - user -c` is the same on Linux and Solaris.
  if [ "$(id -un)" = "$ORACLE_USER" ]; then
    sh -c "export ORACLE_HOME='$ORACLE_HOME'; export PATH=\"\$PATH:$ORACLE_HOME/bin:$ORACLE_HOME/OPatch\"; $*"
  else
    su - "$ORACLE_USER" -c "export ORACLE_HOME='$ORACLE_HOME'; export PATH=\"\$PATH:$ORACLE_HOME/bin:$ORACLE_HOME/OPatch\"; $*"
  fi
}

# ---- service control: systemd -> SMF -> pidfile ------------------------------
svc_mode() {
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then echo systemd
  elif command -v svcadm >/dev/null 2>&1; then echo smf
  else echo pidfile; fi
}

svc_is_active() {
  case "$(svc_mode)" in
    systemd) systemctl is-active --quiet "$SERVICE" ;;
    smf)     [ "$(svcs -H -o state "$SERVICE" 2>/dev/null)" = "online" ] ;;
    pidfile) pf="/var/run/${SERVICE%.service}.pid"; [ -f "$pf" ] && kill -0 "$(cat "$pf")" 2>/dev/null ;;
  esac
}

svc_stop() {
  log "stopping $SERVICE via $(svc_mode)"
  case "$(svc_mode)" in
    systemd) systemctl stop "$SERVICE" ;;
    smf)     svcadm disable -s "$SERVICE" ;;
    pidfile) pf="/var/run/${SERVICE%.service}.pid"; [ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null; rm -f "$pf" ;;
  esac
  i=0
  while svc_is_active && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
  svc_is_active && return 1
  return 0
}

svc_start() {
  log "starting $SERVICE via $(svc_mode)"
  case "$(svc_mode)" in
    systemd) systemctl start "$SERVICE" ;;
    smf)     svcadm enable -s "$SERVICE" ;;
    pidfile) pf="/var/run/${SERVICE%.service}.pid"; ( while :; do sleep 60; done ) & echo $! > "$pf" ;;
  esac
  i=0
  while ! svc_is_active && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
  svc_is_active
}

# ---- checksum: sha256sum (Linux) -> shasum -> digest (Solaris) ---------------
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v digest >/dev/null 2>&1; then digest -a sha256 "$1"
  else echo "no-sha256-tool"; fi
}
