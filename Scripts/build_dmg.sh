#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/MoyuReader.app"
STAGING_DIR="$ROOT_DIR/build/dmg-root"
DMG_PATH="${1:-$ROOT_DIR/build/MoyuReader-mac.dmg}"
VOLUME_NAME="${VOLUME_NAME:-MoyuReader}"

"$ROOT_DIR/Scripts/build_app.sh" >/dev/null

codesign --force --deep --sign - "$APP_DIR" >/dev/null

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "$DMG_PATH"
