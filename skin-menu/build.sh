#!/bin/bash
set -euo pipefail
sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p out/SkinMenu.framework
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk_path" -miphoneos-version-min=14.0 -fobjc-arc -fmodules -Wall -Wextra -Werror -dynamiclib native/SkinMenu.m -framework Foundation -framework UIKit -framework QuartzCore -framework OpenGLES -Wl,-S -install_name @rpath/SkinMenu.framework/SkinMenu -o out/SkinMenu.framework/SkinMenu
cat > out/SkinMenu.framework/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.skins.menu</string><key>CFBundleName</key><string>SkinMenu</string><key>CFBundleExecutable</key><string>SkinMenu</string><key>CFBundlePackageType</key><string>FMWK</string><key>CFBundleVersion</key><string>6</string><key>CFBundleShortVersionString</key><string>6.0</string><key>MinimumOSVersion</key><string>14.0</string></dict></plist>
PLIST
