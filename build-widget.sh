#!/bin/zsh
# build-widget.sh - compile the ClaudeUsage desktop panel into a .app bundle.
# Requires the Xcode toolchain (swiftc). Re-run after editing the Swift source.
set -e
cd "$(dirname "$0")"

APP="ClaudeUsage.app"
SRC="widget/ClaudeUsageWidget.swift"
EXE="ClaudeUsage"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClaudeUsage</string>
  <key>CFBundleDisplayName</key><string>Claude Usage</string>
  <key>CFBundleIdentifier</key><string>local.claude-usage.widget</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
PLIST

echo "Compiling $SRC ..."
swiftc -O -o "$APP/Contents/MacOS/$EXE" "$SRC" \
  -framework Cocoa -framework SwiftUI -framework Combine

# Ad-hoc sign so the bundle launches without Gatekeeper complaints.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built ./$APP"
