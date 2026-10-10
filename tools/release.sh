#!/bin/bash
# tools/release.sh  build, notarize and staple the app, then zip it: build/Neon-Pup.zip
set -euo pipefail
cd "$(dirname "$0")/.."
IDENTITY="Developer ID Application: Holinic LLC (43YSGDB8TC)"
export OUT=build/release
APP="$OUT/Neon Pup.app"
# Notary credentials live in the login Keychain profile "neonpup-notary" (created once by the maintainer with
# `xcrun notarytool store-credentials neonpup-notary ...`). notarytool is sandboxed and cannot read the
# key from a pipe, and the key must never be written to disk by this script.
notary() { xcrun notarytool submit "$1" --keychain-profile neonpup-notary --wait; }
tools/build.sh
rm -f "$OUT/NeonPup.zip"
ditto -c -k --keepParent "$APP" "$OUT/NeonPup.zip"
notary "$OUT/NeonPup.zip"
xcrun stapler staple "$APP"
# The shareable file is a zip of the notarized, stapled app (Apple's DMG queue stalled on 2026-10-09).
rm -f build/Neon-Pup.zip
ditto -c -k --keepParent "$APP" build/Neon-Pup.zip
spctl -a -vvv "$APP"
echo "release ready: build/Neon-Pup.zip"
