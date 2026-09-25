#!/bin/zsh
# Builds Awake.app next to this script.
set -e
cd "$(dirname "$0")"
APP=Awake.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS
swiftc -O -o $APP/Contents/MacOS/Awake Awake.swift
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Awake</string>
  <key>CFBundleIdentifier</key><string>local.awake</string>
  <key>CFBundleExecutable</key><string>Awake</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.4</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - $APP
echo "Built $(pwd)/$APP"
