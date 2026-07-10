#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP_PATH="${1:-$ROOT_DIR/build/MoyuReader-mac.zip}"
EXTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/moyureader-archive.XXXXXX")"

cleanup() {
    rm -rf "$EXTRACT_DIR"
}
trap cleanup EXIT

test -f "$ZIP_PATH"
ditto -x -k "$ZIP_PATH" "$EXTRACT_DIR"

DMG_PATH="$(find "$EXTRACT_DIR" -maxdepth 1 -type f -name '*.dmg' -print -quit)"
test -n "$DMG_PATH"
"$ROOT_DIR/Scripts/verify_dmg.sh" "$DMG_PATH" >/dev/null

echo "DMG 分发包验证通过：$ZIP_PATH"
