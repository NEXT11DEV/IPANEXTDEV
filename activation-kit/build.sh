#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
OUT="out/ActivationKit.framework"
mkdir -p "$OUT"
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=14.0 -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -dynamiclib native/ActivationKit.m -framework Foundation -framework UIKit -framework Security -install_name '@rpath/ActivationKit.framework/ActivationKit' -o "$OUT/ActivationKit"
cat > "$OUT/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>ActivationKit</string><key>CFBundleIdentifier</key><string>local.activation.kit</string><key>CFBundlePackageType</key><string>FMWK</string><key>CFBundleShortVersionString</key><string>0.1</string><key>CFBundleVersion</key><string>1</string><key>MinimumOSVersion</key><string>14.0</string></dict></plist>
PLIST
xcrun lipo -info "$OUT/ActivationKit"
xcrun nm -gU "$OUT/ActivationKit" | grep -E 'Activation(AccountFrame|AccessActive|ShowLogin)'
printf 'Built unsigned framework; native app integration and full re-signing still required.\n'
