#!/bin/bash
# tools/build.sh  builds and signs build/Neon Pup.app
set -euo pipefail
cd "$(dirname "$0")/.."
ROUTER="${ROUTER:-$(cd ../.. && pwd)}"  # override when building from a worktree
# Your own builds: set IDENTITY to your Developer ID and change the team id in HelperConstants (README).
IDENTITY="${IDENTITY:-Developer ID Application: Holinic LLC (43YSGDB8TC)}"
OUT="${OUT:-build}"
APP="$OUT/Neon Pup.app"
mkdir -p "$OUT"
tools/fetch-sing-box.sh 1.13.7 build/cache
# Source paths baked into the binary (#file in runtime messages) would show the builder's home folder.
MAP=(-Xswiftc -file-prefix-map -Xswiftc "$PWD=NeonPup" -Xswiftc -file-prefix-map -Xswiftc "$HOME=~")
swift build -c release --arch arm64 --arch x86_64 "${MAP[@]}"
BIN=$(swift build -c release --arch arm64 --arch x86_64 "${MAP[@]}" --show-bin-path)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Art" "$APP/Contents/Library/LaunchDaemons"
cp "$BIN/NeonPup" "$BIN/NeonPupHelper" "$APP/Contents/MacOS/"
cp build/cache/sing-box-universal "$APP/Contents/Resources/sing-box"
# No server details in the app (own roads, 2026-10-10): people add their roads in the app.
# China IP and domain lists ("China sites go direct"). Uses the router repo's copies when present,
# otherwise downloads sing-box's published rule sets (public builds).
RULES="$ROUTER/clients/sarah"
if [ ! -f "$RULES/geoip-cn.srs" ] || [ ! -f "$RULES/geosite-cn.srs" ]; then
  RULES=build/cache/rules
  mkdir -p "$RULES"
  SRC="https://raw.githubusercontent.com/SagerNet"
  [ -f "$RULES/geoip-cn.srs" ] || curl -fsSL -o "$RULES/geoip-cn.srs" "$SRC/sing-geoip/rule-set/geoip-cn.srs"
  [ -f "$RULES/geosite-cn.srs" ] || curl -fsSL -o "$RULES/geosite-cn.srs" "$SRC/sing-geosite/rule-set/geosite-cn.srs"
fi
cp "$RULES/geoip-cn.srs" "$RULES/geosite-cn.srs" "$APP/Contents/Resources/"
cp packaging/Info.plist "$APP/Contents/Info.plist"
cp packaging/co.holinic.neonpup.helper.plist "$APP/Contents/Library/LaunchDaemons/"
ls Art/*.png >/dev/null 2>&1 && cp Art/*.png "$APP/Contents/Resources/Art/"
[ -f Art/AppIcon.icns ] && cp Art/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP/Contents/Resources/sing-box"
codesign --force --timestamp --options runtime --identifier co.holinic.neonpup.helper --sign "$IDENTITY" "$APP/Contents/MacOS/NeonPupHelper"
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"
echo "built $APP"
