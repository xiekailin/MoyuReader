#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DMG_PATH="${1:-$ROOT_DIR/build/MoyuReader-mac.dmg}"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/moyureader-dmg.XXXXXX")"

cleanup() {
    hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

test -f "$DMG_PATH"
hdiutil verify "$DMG_PATH" >/dev/null

DMG_ATTRIBUTES="$(GetFileInfo -a "$DMG_PATH")"
[[ "$DMG_ATTRIBUTES" == *C* ]]
xattr -p com.apple.ResourceFork "$DMG_PATH" >/dev/null

hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -readonly -quiet
test -f "$MOUNT_DIR/.VolumeIcon.icns"
test -d "$MOUNT_DIR/MoyuReader.app"
test -L "$MOUNT_DIR/Applications"

VOLUME_ATTRIBUTES="$(GetFileInfo -a "$MOUNT_DIR")"
[[ "$VOLUME_ATTRIBUTES" == *C* ]]

codesign --verify --deep --strict "$MOUNT_DIR/MoyuReader.app"

echo "DMG 验证通过：$DMG_PATH"
