#!/bin/sh
# Builds a fake Oracle patch archive in the MOS naming style, plus a .sha256
# sidecar. Both files get hosted on public HTTPS and attached to the Tanium
# "Stage" package as remote files.
#
#   ./build_patch_zip.sh [patch_id] [release] [platform]
#   -> dist/p12345678_190000_Linux-x86-64.zip
#   -> dist/p12345678_190000_Linux-x86-64.zip.sha256
set -eu
PATCH_ID="${1:-12345678}"
RELEASE="${2:-190000}"
PLATFORM="${3:-Linux-x86-64}"
NAME="p${PATCH_ID}_${RELEASE}_${PLATFORM}.zip"
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
OUT="$HERE/dist"
mkdir -p "$OUT" "$WORK/$PATCH_ID/etc/config" "$WORK/$PATCH_ID/files/lib"

cat > "$WORK/$PATCH_ID/README.txt" <<EOF
Patch $PATCH_ID  (SIMULATED - lab use only)
Database Release Update : 19.24.0.0.240716
Platform: $PLATFORM

Apply:    cd $PATCH_ID && opatch apply -silent
Rollback: opatch rollback -id $PATCH_ID -silent
EOF

cat > "$WORK/$PATCH_ID/etc/config/inventory.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<oneoff_inventory>
  <patch_id>$PATCH_ID</patch_id>
  <reference_id>$PATCH_ID</reference_id>
  <base_bugs><bug number="$PATCH_ID" description="DATABASE RELEASE UPDATE 19.24.0.0.0 (SIMULATED)"/></base_bugs>
  <platform>$PLATFORM</platform>
  <release>19.0.0.0.0</release>
</oneoff_inventory>
EOF

cat > "$WORK/$PATCH_ID/etc/config/actions.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<actions>
  <copy_file source="files/lib/libserver19.a" target="lib/libserver19.a"/>
</actions>
EOF
head -c 65536 /dev/urandom > "$WORK/$PATCH_ID/files/lib/libserver19.a"

rm -f "$OUT/$NAME" "$OUT/$NAME.sha256"
( cd "$WORK" && zip -qr "$OUT/$NAME" "$PATCH_ID" )
( cd "$OUT" && sha256sum "$NAME" > "$NAME.sha256" )
rm -rf "$WORK"
echo "built:"; ls -l "$OUT/$NAME" "$OUT/$NAME.sha256"; cat "$OUT/$NAME.sha256"
