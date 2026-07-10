#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/build/MoyuReader.app"
DMG_PATH="${1:-$ROOT_DIR/build/MoyuReader-mac.dmg}"
VOLUME_NAME="${VOLUME_NAME:-MoyuReader}"
ICON_PATH="$ROOT_DIR/Resources/AppIcon.icns"
mkdir -p "$ROOT_DIR/build"
if [[ "$DMG_PATH" != /* ]]; then
    DMG_PATH="$PWD/$DMG_PATH"
fi
ZIP_PATH="${DMG_PATH%.dmg}.zip"
WORK_DIR="$(mktemp -d "$ROOT_DIR/build/dmg-work.XXXXXX")"
STAGING_DIR="$WORK_DIR/root"
MOUNT_DIR="$WORK_DIR/mount"
READ_WRITE_DMG="$WORK_DIR/MoyuReader-rw.dmg"
VOLUME_ATTACHED=false

cleanup() {
    if [[ "$VOLUME_ATTACHED" == true ]]; then
        hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

"$ROOT_DIR/Scripts/build_app.sh" >/dev/null

codesign --force --deep --sign - "$APP_DIR" >/dev/null

rm -f "$DMG_PATH" "$ZIP_PATH"
mkdir -p "$STAGING_DIR" "$MOUNT_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    "$READ_WRITE_DMG" >/dev/null

hdiutil attach \
    "$READ_WRITE_DMG" \
    -mountpoint "$MOUNT_DIR" \
    -nobrowse \
    -readwrite \
    -quiet
VOLUME_ATTACHED=true

cp "$ICON_PATH" "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -a C "$MOUNT_DIR"

hdiutil detach "$MOUNT_DIR" -quiet
VOLUME_ATTACHED=false

hdiutil convert \
    "$READ_WRITE_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH" >/dev/null

cp "$ICON_PATH" "$WORK_DIR/AppIcon.icns"
printf "read 'icns' (-16455) \"AppIcon.icns\";\n" > "$WORK_DIR/AppIcon.r"
(cd "$WORK_DIR" && Rez -append AppIcon.r -o "$DMG_PATH")
SetFile -a C "$DMG_PATH"

"$ROOT_DIR/Scripts/verify_dmg.sh" "$DMG_PATH" >/dev/null

(cd "$(dirname "$DMG_PATH")" && \
    ditto -c -k --sequesterRsrc "$(basename "$DMG_PATH")" "$ZIP_PATH")
"$ROOT_DIR/Scripts/verify_dmg_archive.sh" "$ZIP_PATH" >/dev/null

echo "DMG：$DMG_PATH"
echo "分发包：$ZIP_PATH"
