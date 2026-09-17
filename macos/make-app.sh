#!/bin/zsh
# BookLand — Copyright (c) 2026 Mohammad Ayati
# Licensed under the MIT License. See LICENSE.
set -euo pipefail

BUILD_ROOT="${PWD}/.quiet-build"
MODULE_CACHE="${BUILD_ROOT}/ModuleCache"
mkdir -p "${MODULE_CACHE}"

xcrun swiftc \
  -sdk "$(xcrun --show-sdk-path)" \
  -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "${MODULE_CACHE}" \
  Sources/BookLandApp/*.swift \
  -o "${BUILD_ROOT}/BookLand" \
  -framework SwiftUI \
  -framework AppKit \
  -framework PDFKit
APP_ROOT="${PWD}/BookLand.app"
CONTENTS="${APP_ROOT}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

rm -rf "${APP_ROOT}"
mkdir -p "${MACOS}" "${RESOURCES}"
cp "${BUILD_ROOT}/BookLand" "${MACOS}/BookLand"
cp AppIcon.icns "${RESOURCES}/AppIcon.icns" 2>/dev/null || true

cat > "${CONTENTS}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key><string>BookLand</string>
	<key>CFBundleExecutable</key><string>BookLand</string>
	<key>CFBundleIdentifier</key><string>local.bookland.app</string>
	<key>CFBundleName</key><string>BookLand</string>
	<key>CFBundleIconFile</key><string>AppIcon.icns</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>NSHumanReadableCopyright</key><string>© Mohammad Ayati, August 2026. BookLand logo artwork and logo-specific visual identity credited to Lida Samadi (GitHub: @lidasama; Instagram: @lidasamadi.design). Source code is licensed under the MIT License.</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Built ${APP_ROOT}"
