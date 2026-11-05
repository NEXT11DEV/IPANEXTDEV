#!/bin/bash
set -euo pipefail
sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p out/SkinProbe.framework
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk_path" -miphoneos-version-min=14.0 -fobjc-arc -fmodules -Wall -Wextra -Werror -dynamiclib native/SkinProbe.m -framework Foundation -framework UIKit -install_name @rpath/SkinProbe.framework/SkinProbe -o out/SkinProbe.framework/SkinProbe
cat > out/SkinProbe.framework/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.skins.probe</string><key>CFBundleName</key><string>SkinProbe</string><key>CFBundleExecutable</key><string>SkinProbe</string><key>CFBundlePackageType</key><string>FMWK</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string><key>MinimumOSVersion</key><string>14.0</string></dict></plist>
PLIST
