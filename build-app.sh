#!/bin/bash
# Builds dist/BetterGI.app (self-contained, Apple Silicon). Needs: .NET 10 SDK, Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"
export PATH="$HOME/.dotnet:$PATH" DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
[ -d "$HOME/.dotnet" ] && export DOTNET_ROOT="$HOME/.dotnet"

native/BgiMacNative/build.sh

APP=dist/BetterGI.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
dotnet publish src/BetterGI.Mac -c Release -r osx-arm64 --self-contained true \
  -p:DebugType=none -o "$APP/Contents/MacOS" -clp:ErrorsOnly
cp src/BetterGI.Mac/Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

VERSION=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' src/BetterGI.Mac/BetterGI.Mac.csproj)
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>BetterGI</string>
  <key>CFBundleDisplayName</key><string>BetterGI</string>
  <key>CFBundleIdentifier</key><string>com.bettergi.mac</string>
  <key>CFBundleExecutable</key><string>BetterGI</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signature. macOS ties the Screen Recording / Accessibility grants to this signature, so they
# have to be granted again after every rebuild unless a stable signing identity is used:
#   CODESIGN_IDENTITY="My Cert Name" ./build-app.sh
if [ -n "${CODESIGN_IDENTITY:-}" ] && [ "${CODESIGN_IDENTITY}" != "-" ]; then
  # Notarisation requires the hardened runtime; the .NET runtime then needs these entitlements for its JIT.
  codesign --force --deep --options runtime --timestamp --entitlements packaging/entitlements.plist \
    --sign "$CODESIGN_IDENTITY" "$APP"
else
  codesign --force --deep --sign - "$APP"
fi
echo "built $(pwd)/$APP"
