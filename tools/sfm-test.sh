#!/bin/bash
# tools/sfm-test.sh  live checks for Neon Pup on SFM. No sudo. Run while Neon Pup says Connected.
# Prints PASS/FAIL per check; a check that can't run says SKIP.
set -uo pipefail
fail=0
pass() { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=1; }

ID=$(scutil --nc list | grep '\[VPN:io.nekohasekai.sfamt.standalone\]' | grep -oE '[0-9A-F-]{36}' | head -1)
[ -n "$ID" ] || { echo "FAIL no SFM VPN found (run the setup wizard)"; exit 1; }
if [ "$(scutil --nc status "$ID" | head -1)" = "Connected" ]; then pass "SFM tunnel connected"
else bad "SFM tunnel not connected (press Wake me up first; the checks below then mean nothing)"; fi

# Exit country: only meaningful through the tunnel, and it must be a server's country, never CN or the local one.
iface=$(route -n get 1.1.1.1 | awk '/interface:/{print $2}')
v4=$(curl -4 -s --max-time 12 https://www.cloudflare.com/cdn-cgi/trace | grep -E '^loc=' | cut -d= -f2)
if [[ "$iface" == utun* ]] && [ -n "$v4" ] && [ "$v4" != "CN" ]; then pass "IPv4 goes through the tunnel ($iface) and exits in $v4"
else bad "IPv4 goes out via ${iface:-?} and exits in '${v4:-none}'"; fi
v6=$(curl -6 -s --max-time 12 https://www.cloudflare.com/cdn-cgi/trace | grep -E '^loc=' | cut -d= -f2)
iface6=$(route -n get -inet6 2606:4700:4700::1111 2>/dev/null | awk '/interface:/{print $2}')
if [ -z "$v6" ]; then echo "SKIP IPv6 (no IPv6 on this network)"
elif [[ "$iface6" == utun* ]] && [ "$v6" != "CN" ]; then pass "IPv6 goes through the tunnel ($iface6) and exits in $v6"
else bad "IPv6 goes out via ${iface6:-?} and exits in $v6"; fi

primary=$(scutil --dns | awk '/^resolver #1/{f=1} f && /nameserver\[0\]/{print $3; exit}')
[ "$primary" = "172.19.0.2" ] && pass "macOS sends DNS into the tunnel ($primary)" || bad "macOS DNS goes to ${primary:-?}"
resolver=$(python3 -c "import socket;print(socket.gethostbyname('whoami.akamai.net'))" 2>/dev/null)
echo "INFO resolver seen by the internet: $resolver (compare with a lookup with Neon Pup off)"

SECRET=$(defaults read co.holinic.neonpup sfmAPISecret 2>/dev/null)
TOKEN=$(defaults read co.holinic.neonpup sfmProfileToken 2>/dev/null)
API=http://127.0.0.1:47321
if [ -n "$SECRET" ]; then
  claude=$(curl -s -H "Authorization: Bearer $SECRET" "$API/proxies/claude" | python3 -c "import json,sys;print(json.load(sys.stdin).get('now',''))" 2>/dev/null)
  [ -n "$claude" ] && pass "Claude is on $claude" || bad "Claude's server unknown (control API not reachable)"
  mode=$(curl -s -H "Authorization: Bearer $SECRET" "$API/configs" | python3 -c "import json,sys;print(json.load(sys.stdin).get('mode',''))" 2>/dev/null)
  echo "INFO engine mode: $mode (Rule = Chinese sites direct, Global = through your servers)"
  if [ -n "$TOKEN" ]; then
    want=$(curl -s "http://127.0.0.1:47322/$TOKEN.json" | python3 -c "import json,sys;print([o['tag'] for o in json.load(sys.stdin)['outbounds'] if o['tag'].startswith('np-')][0])" 2>/dev/null)
    code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $SECRET" "$API/proxies/$want")
    [ "$code" = "200" ] && pass "SFM runs the current server list ($want)" || bad "SFM runs an older server list (press refresh in SFM)"
  else echo "SKIP fingerprint (no profile token)"; fi
else echo "SKIP control API checks (no secret; is setup done?)"; fi

[ $fail = 0 ] && echo "ALL PASS" || echo "SOME CHECKS FAILED"
exit $fail
