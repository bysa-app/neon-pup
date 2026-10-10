#!/bin/bash
# tools/fetch-sing-box.sh  usage: fetch-sing-box.sh <version> <cache-dir>
set -euo pipefail
V="$1"; OUT="$2"; mkdir -p "$OUT"
if [ -x "$OUT/sing-box-universal" ] && "$OUT/sing-box-universal" version | head -1 | grep -qx "sing-box version $V"; then exit 0; fi
API=$(curl -fsSL "https://api.github.com/repos/SagerNet/sing-box/releases/tags/v$V")
for arch in arm64 amd64; do
  name="sing-box-$V-darwin-$arch.tar.gz"
  want=$(printf '%s' "$API" | python3 -c '
import json, sys
name = sys.argv[1]
d = [a.get("digest") for a in json.load(sys.stdin)["assets"] if a["name"] == name]
if not d or not d[0]: sys.exit("no digest published for " + name)
print(d[0].split(":", 1)[1])' "$name")
  curl -fsSL -o "$OUT/$name" "https://github.com/SagerNet/sing-box/releases/download/v$V/$name"
  got=$(shasum -a 256 "$OUT/$name" | cut -d' ' -f1)
  [ "$got" = "$want" ] || { echo "sha256 mismatch for $name: $got != $want"; exit 1; }
  tar -xzf "$OUT/$name" -C "$OUT"
done
lipo -create "$OUT/sing-box-$V-darwin-arm64/sing-box" "$OUT/sing-box-$V-darwin-amd64/sing-box" -output "$OUT/sing-box-universal"
lipo -info "$OUT/sing-box-universal"
