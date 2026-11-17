#!/bin/bash
# Builds dist/BetterGI-<version>-arm64.dmg: a drag-to-Applications disk image of BetterGI.app.
#   ./build-dmg.sh              rebuild the app, then package it
#   ./build-dmg.sh --no-build   package the existing dist/BetterGI.app as it is
#
# Signing: with no CODESIGN_IDENTITY the app is ad-hoc signed, and macOS Gatekeeper will refuse to open it
# on other Macs until the user allows it (see INSTALL.txt in the image). For a build that opens normally
# everywhere, sign with an Apple "Developer ID Application" certificate and notarise:
#   CODESIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=<keychain profile> ./build-dmg.sh
# (create the profile once with: xcrun notarytool store-credentials <keychain profile>)
set -euo pipefail
cd "$(dirname "$0")"

APP=dist/BetterGI.app
if [ "${1:-}" != "--no-build" ]; then
  ./build-app.sh
fi
[ -d "$APP" ] || { echo "missing $APP (run without --no-build)"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/BetterGI-$VERSION-arm64.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# ditto keeps the code signature, extended attributes and symlinks intact.
ditto "$APP" "$STAGE/BetterGI.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/INSTALL.txt" <<'TXT'
BetterGI for Mac
================

Install
  Drag BetterGI onto the Applications folder, then open it from Applications.
  Requires an Apple Silicon Mac with macOS 13 or later.

First start
  macOS may say the app cannot be opened because the developer cannot be verified
  (this build is not notarised by Apple). To allow it:
    1. Try to open BetterGI once and dismiss the message.
    2. Open System Settings > Privacy & Security, scroll down and click "Open Anyway".
  If macOS says the app "is damaged", run this in Terminal and open it again:
    xattr -dr com.apple.quarantine /Applications/BetterGI.app

Permissions
  BetterGI asks for two permissions in System Settings > Privacy & Security:
    Screen & System Audio Recording   to see the game window
    Accessibility                     to send keys and mouse input
  Quit and reopen BetterGI after enabling Screen Recording.
  After installing a new version, remove BetterGI from both lists with "-" and grant them again.

Use
  Start the game with Yaagl, pick its window in BetterGI and press "Start capture".

BetterGI is free software under the GNU GPL v3 (see LICENSE).
Upstream project: https://github.com/babalae/better-genshin-impact
TXT
cp upstream/LICENSE "$STAGE/LICENSE"

rm -f "$DMG"
hdiutil create -volname "BetterGI $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -quiet "$DMG"

if [ -n "${CODESIGN_IDENTITY:-}" ] && [ "${CODESIGN_IDENTITY}" != "-" ]; then
  codesign --force --sign "$CODESIGN_IDENTITY" "$DMG"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

echo "built $(pwd)/$DMG ($(du -h "$DMG" | cut -f1))"
