#!/bin/bash
set -euo pipefail
sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p out/SkinMenu.framework
bash ../activation-kit/build.sh
cp ../activation-kit/out/ActivationKit.framework/ActivationKit out/SkinMenu.framework/ActivationKit.bin
cp ../activation-kit/out/ActivationKit.framework/Info.plist out/SkinMenu.framework/ActivationKit.plist
python3 - <<'PYDIGEST'
import struct,hashlib
from pathlib import Path
b=Path('out/SkinMenu.framework/ActivationKit.bin').read_bytes();p=32;section=None
for _ in range(struct.unpack_from('<I',b,16)[0]):
 cmd,size=struct.unpack_from('<II',b,p)
 if cmd==25:
  q=p+72
  for i in range(struct.unpack_from('<I',b,p+64)[0]):
   if b[q:q+16].split(bytes([0]))[0]==b'__text':
    addr,length,offset=struct.unpack_from('<QQI',b,q+32);section=b[offset:offset+length]
   q+=80
 p+=size
assert section
digest=hashlib.sha256(section).digest()
text='#define ACTIVATION_TEXT_SIZE '+str(len(section))+'\n#define ACTIVATION_TEXT_DIGEST {'+','.join(hex(x) for x in digest)+'}\n'
text+='static const unsigned char EXPECTED_GAME_UUID[16]={0x59,0x24,0x3e,0x6b,0xa7,0xf2,0x36,0x7,0x95,0xd6,0xf3,0x18,0x6b,0xab,0x44,0x90};\n'
Path('out/ActivationDigest.h').write_text(text)
PYDIGEST
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$sdk_path" -miphoneos-version-min=14.0 -fobjc-arc -fmodules -Iout -Wall -Wextra -Werror -dynamiclib native/SkinMenu.m -framework Foundation -framework UIKit -framework QuartzCore -framework OpenGLES -framework ImageIO -Wl,-S -install_name @rpath/SkinMenu.framework/SkinMenu -o out/SkinMenu.framework/SkinMenu
cat > out/SkinMenu.framework/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.skins.menu</string><key>CFBundleName</key><string>SkinMenu</string><key>CFBundleExecutable</key><string>SkinMenu</string><key>CFBundlePackageType</key><string>FMWK</string><key>CFBundleVersion</key><string>8</string><key>CFBundleShortVersionString</key><string>8.0</string><key>MinimumOSVersion</key><string>14.0</string></dict></plist>
PLIST
