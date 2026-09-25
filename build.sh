#!/bin/zsh
# Builds Jiggler.app next to this script.
set -e
cd "$(dirname "$0")"
APP=Jiggler.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS
swiftc -O -o $APP/Contents/MacOS/Jiggler Jiggler.swift
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Jiggler</string>
  <key>CFBundleIdentifier</key><string>local.jiggler</string>
  <key>CFBundleExecutable</key><string>Jiggler</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - $APP
echo "Built $(pwd)/$APP"
