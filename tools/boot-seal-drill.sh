#!/bin/bash
# tools/boot-seal-drill.sh  checks the boot policy (Codex review 2026-10-10, bricking #1) on the real helper.
# Needs sudo. A policy simulation, not a reboot: pf rules are cleared (a reboot clears them), a flag is left on
# disk, and launchd relaunches the helper. Ends with normal internet and China mode off.
set -uo pipefail
A="/Applications/Neon Pup.app/Contents/MacOS/NeonPup"
S=/private/var/db/co.holinic.neonpup
ANCHOR=com.apple/co.holinic.neonpup
fail=0
reach() { curl -s -o /dev/null -w '%{http_code}' --max-time 6 https://www.cloudflare.com/cdn-cgi/trace; }
rules() { sudo pfctl -a "$ANCHOR" -s rules 2>/dev/null | grep -v -c ALTQ; }
check() { if [ "$2" = "$3" ]; then echo "   ok   $1: $2"; else echo "   FAIL $1: $2 (want $3)"; fail=1; fi; }
cleanup() {
  sudo rm -f "$S/killswitch-wanted" "$S/killswitch-china"
  sudo pfctl -a "$ANCHOR" -F all >/dev/null 2>&1
  defaults write co.holinic.neonpup chinaMode -bool false
}
trap cleanup EXIT

echo "== setup"
sudo -v || exit 1
osascript -e 'tell application id "co.holinic.neonpup" to quit' >/dev/null 2>&1; sleep 2
pgrep -x NeonPup >/dev/null && { echo "FAIL: Neon Pup is still running"; exit 1; }
"$A" --spike stop >/dev/null 2>&1
# Short Swift strings like the version number don't show up in `strings`; the China flag name does.
strings "/Applications/Neon Pup.app/Contents/MacOS/NeonPupHelper" | grep -q killswitch-china \
  || { echo "FAIL: the installed helper predates this fix (install the new version first)"; exit 1; }
# kern.boottime prints "{ sec = 1791016552, usec = 514315 } ...": take the sec field only (Codex review #7).
boot=$(sysctl -n kern.boottime | sed -nE 's/^\{ sec = ([0-9]+),.*/\1/p')
[[ "$boot" =~ ^[0-9]+$ ]] || { echo "FAIL: could not read the boot time"; exit 1; }
echo "   boot $boot"

restart_with() {  # $1 = recorded boot ("" = legacy empty file), $2 = China mode (yes/no)
  sudo pfctl -a "$ANCHOR" -F all >/dev/null 2>&1
  printf '%s' "$1" | sudo tee "$S/killswitch-wanted" >/dev/null || { echo "FAIL: could not write the flag"; exit 1; }
  if [ "$2" = yes ]; then sudo touch "$S/killswitch-china"; else sudo rm -f "$S/killswitch-china"; fi
  sudo launchctl kickstart -k system/co.holinic.neonpup.helper >/dev/null 2>&1 || { echo "FAIL: helper did not restart"; exit 1; }
  sleep 4
}
flag() { sudo test -e "$S/killswitch-wanted" && echo present || echo gone; }

echo "1 flag from an earlier boot, China mode off (power cut while connected outside China)"
restart_with 1000000000 no; check "rules" "$(rules)" 0; check "flag" "$(flag)" gone; check "internet" "$(reach)" 200
echo "2 flag from an earlier boot, China mode on"
restart_with 1000000000 yes; [ "$(rules)" -gt 0 ] && check "rules" sealed sealed || check "rules" none sealed; check "internet" "$(reach)" 000
echo "3 flag from this boot, China mode off (helper crash mid-session)"
restart_with "$boot" no; [ "$(rules)" -gt 0 ] && check "rules" sealed sealed || check "rules" none sealed; check "internet" "$(reach)" 000
echo "4 empty flag from an older version, China mode off"
restart_with "" no; check "rules" "$(rules)" 0; check "flag" "$(flag)" gone; check "internet" "$(reach)" 200

echo "== cleanup"
cleanup; trap - EXIT
check "rules after cleanup" "$(rules)" 0
check "internet after cleanup" "$(reach)" 200
open "/Applications/Neon Pup.app"; sleep 6
check "internet after reopening (China mode off)" "$(reach)" 200
[ $fail = 0 ] && echo "PASS" || echo "FAIL"
exit $fail
