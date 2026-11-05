#!/bin/bash
set -euo pipefail
sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p out/SkinLab.framework
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk_path" -miphoneos-version-min=14.0 -fobjc-arc -fmodules -Wall -Wextra -Werror -dynamiclib native/SkinLab.m -framework Foundation -framework UIKit -install_name @rpath/SkinLab.framework/SkinLab -o out/SkinLab.framework/SkinLab
cat > out/SkinLab.framework/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.skins.lab</string><key>CFBundleName</key><string>SkinLab</string><key>CFBundleExecutable</key><string>SkinLab</string><key>CFBundlePackageType</key><string>FMWK</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string><key>MinimumOSVersion</key><string>14.0</string></dict></plist>
PLIST
