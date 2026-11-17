#!/bin/bash
# Builds libBgiMacNative.dylib (universal: arm64 + x86_64) using only the Xcode Command Line Tools.
# Output: native/BgiMacNative/build/libBgiMacNative.dylib
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
SDK="$(xcrun --show-sdk-path)"
MIN=13.0
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library -emit-library \
    -module-name BgiMacNative \
    -sdk "$SDK" -target "$ARCH-apple-macos$MIN" \
    -Xlinker -install_name -Xlinker @rpath/libBgiMacNative.dylib \
    -o "build/libBgiMacNative.$ARCH.dylib" BgiMacNative.swift Win32Compat.swift
done
lipo -create build/libBgiMacNative.arm64.dylib build/libBgiMacNative.x86_64.dylib -output build/libBgiMacNative.dylib
rm -f build/libBgiMacNative.arm64.dylib build/libBgiMacNative.x86_64.dylib
codesign --force --sign - build/libBgiMacNative.dylib
echo "built $(pwd)/build/libBgiMacNative.dylib"
