#!/bin/bash
# Baut Quarry.app ohne Xcode und installiert sie nach /Programme.
#   ./build-app.sh            → bauen + installieren + öffnen
#   ./build-app.sh --no-install → nur bauen (für release.sh)
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
REPO=$(cat .update-repo 2>/dev/null || true) # „besitzer/quarry“ für den Updater

# shortcut: das macOS-27-SDK braucht für @State Xcodes SwiftUIMacros-Plugin; mit installiertem Xcode diese Zeile löschen.
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
swift build -c release 2>&1 | grep -v "ld: warning" || true

APP=build/Quarry.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Quarry "$APP/Contents/MacOS/Quarry"
cp icon/Quarry.icns "$APP/Contents/Resources/Quarry.icns"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Quarry</string>
  <key>CFBundleDisplayName</key><string>Quarry</string>
  <key>CFBundleIdentifier</key><string>local.quarry.launcher</string>
  <key>CFBundleExecutable</key><string>Quarry</string>
  <key>CFBundleIconFile</key><string>Quarry</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>QuarryUpdateRepo</key><string>$REPO</string>
</dict></plist>
EOF
codesign --force --deep --sign - "$APP"
echo "Gebaut: Quarry $VERSION${REPO:+ (Updates von github.com/$REPO)}"

if [[ "${1:-}" != "--no-install" ]]; then
  pkill -x Quarry 2>/dev/null || true
  rm -rf /Applications/Quarry.app
  ditto "$APP" /Applications/Quarry.app
  open /Applications/Quarry.app
  echo "Installiert: /Applications/Quarry.app"
fi
