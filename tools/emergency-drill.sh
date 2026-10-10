#!/bin/bash
# tools/emergency-drill.sh  proves the guide's Emergency line gets a sealed Mac back online. Needs sudo.
# It runs the line exactly as docs/GUIDE.md prints it. Always restores normal internet at the end.
set -uo pipefail
cd "$(dirname "$0")/.."
A="/Applications/Neon Pup.app/Contents/MacOS/NeonPup"
LINE=$(grep -m1 '^pkill -x NeonPup;' docs/GUIDE.md)
[ -n "$LINE" ] || { echo "FAIL: emergency line not found in docs/GUIDE.md"; exit 1; }
trap '"$A" --spike killswitch off >/dev/null 2>&1' EXIT
reach() { curl -s -o /dev/null -w '%{http_code}' --max-time 6 https://www.cloudflare.com/cdn-cgi/trace; }
fail=0

echo "== set up a stuck Mac: China mode on, engine stopped, block on"
open "/Applications/Neon Pup.app"; sleep 3
defaults write co.holinic.neonpup chinaMode -bool true
"$A" --spike stop >/dev/null 2>&1
"$A" --spike killswitch on
r=$(reach); echo "1 sealed: $r (must be 000)"; [ "$r" = "000" ] || fail=1
sudo test -e /private/var/db/co.holinic.neonpup/killswitch-wanted && echo "2 block wanted flag present (expected)" || { echo "2 FAIL: flag missing"; fail=1; }

echo "== run the guide's line"
bash -c "$LINE" 2>&1 | grep -v -E 'ALTQ|^$' | sed 's/^/   /'
sleep 2
r=$(reach); echo "3 after the line: $r (must be 200)"; [ "$r" = "200" ] || fail=1
sudo test -e /private/var/db/co.holinic.neonpup/killswitch-wanted && { echo "4 FAIL: block wanted flag still there"; fail=1; } || echo "4 block wanted flag gone"
rules=$(sudo pfctl -a com.apple/co.holinic.neonpup -s rules 2>/dev/null | grep -v ALTQ)
[ -z "$rules" ] && echo "5 no Neon Pup rules left" || { echo "5 FAIL: rules left"; fail=1; }
[ "$(defaults read co.holinic.neonpup chinaMode)" = "0" ] && echo "6 China mode off" || { echo "6 FAIL: China mode still on"; fail=1; }
pgrep -x NeonPup >/dev/null && { echo "7 FAIL: app still running"; fail=1; } || echo "7 app quit"

echo "== reopen the app: it must not block again"
open "/Applications/Neon Pup.app"; sleep 6
r=$(reach); echo "8 after reopening: $r (must be 200)"; [ "$r" = "200" ] || fail=1
[ $fail = 0 ] && echo "PASS" || echo "FAIL"
exit $fail
