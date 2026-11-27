#!/usr/bin/env bash
# Builds Vocality with SwiftPM and wraps it in a signed .app bundle.
# Usage: scripts/bundle.sh [output-dir]   (default: ~/Downloads)
set -euo pipefail

cd "$(dirname "$0")/.."
OUT_DIR="${1:-$HOME/Downloads}"
VERSION="3.0.0"
BUILD="300"
APP="build/Vocality.app"

if ! xcodebuild -version >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "Building…"
swift build -c release --arch arm64

rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/arm64-apple-macosx/release/Vocality "$APP/Contents/MacOS/Vocality"
[ -f Resources/AppIcon.icns ] || swift scripts/make-icon.swift Resources/AppIcon.icns
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.taylorle9212.Vocality</string>
    <key>CFBundleName</key><string>Vocality</string>
    <key>CFBundleDisplayName</key><string>Vocality</string>
    <key>CFBundleExecutable</key><string>Vocality</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key><string>Vocality records audio while the fn shortcut is held.</string>
</dict>
</plist>
PLIST

# Sign with the only Apple Development identity if there is exactly one, else ad-hoc.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDS=$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development: / { print $2 }')
    [ "$(printf '%s\n' "$IDS" | awk 'NF' | wc -l | tr -d ' ')" = "1" ] && IDENTITY="$IDS" || IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
echo "Signed with: $([ "$IDENTITY" = "-" ] && echo ad-hoc || echo "$IDENTITY")"

mkdir -p "$OUT_DIR"
rm -rf "$OUT_DIR/Vocality.app"
ditto "$APP" "$OUT_DIR/Vocality.app"
echo "Built $OUT_DIR/Vocality.app ($(du -sh "$OUT_DIR/Vocality.app" | cut -f1))"
