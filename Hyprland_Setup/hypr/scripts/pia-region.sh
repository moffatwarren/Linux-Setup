#!/usr/bin/env bash
# Resolve which PIA region the tunnel actually exits through.
#
# `piactl get region` reports the *selected* region, which is normally "auto"
# and so says nothing about where you ended up. This maps the current exit IP
# against PIA's own published server list (first party, no geolocation service)
# and prints a human-readable region name, or nothing if it cannot be resolved.
#
# Prints an empty line rather than guessing: a /24 is shared by more than one
# region about a quarter of the time, and a few of those span countries
# (82.139.195.0/24 is both Algeria and Egypt), so an ambiguous subnet is
# reported as unknown instead of a confidently wrong answer.

set -uo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/pia-serverlist.json"
URL="https://serverlist.piaservers.net/vpninfo/servers/v6"
MAX_AGE=$((7 * 24 * 3600))

refresh_cache() {
    local age
    if [ -f "$CACHE" ]; then
        age=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
        [ "$age" -lt "$MAX_AGE" ] && return 0
    fi
    mkdir -p "$(dirname "$CACHE")"
    if curl -s --max-time 10 -o "$CACHE.tmp" "$URL" && [ -s "$CACHE.tmp" ]; then
        mv "$CACHE.tmp" "$CACHE"
    else
        rm -f "$CACHE.tmp"
    fi
}

current_exit_ip() {
    # When connected, the public IP is the gateway we exit through.
    local ip
    ip=$(piactl get pubip 2>/dev/null)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "$ip"
        return
    fi
    # Fall back to whichever server the generated OpenVPN config points at.
    grep -m1 '^remote ' /opt/piavpn/var/pia.ovpn 2>/dev/null | awk '{print $2}'
}

main() {
    [ "$(piactl get connectionstate 2>/dev/null)" = "Connected" ] || { echo ""; exit 0; }

    local ip
    ip=$(current_exit_ip)
    [ -n "$ip" ] || { echo ""; exit 0; }

    refresh_cache
    [ -f "$CACHE" ] || { echo ""; exit 0; }

    python3 - "$CACHE" "$ip" <<'PY'
import json, sys

cache, ip = sys.argv[1], sys.argv[2]
try:
    with open(cache, encoding="utf-8") as f:
        servers = json.loads(f.readline())
except Exception:
    print("")
    raise SystemExit

prefix = ".".join(ip.split(".")[:3]) + "."
exact, subnet = set(), set()
for region in servers.get("regions", []):
    name = region.get("name")
    for group in (region.get("servers") or {}).values():
        for server in group:
            sip = server.get("ip", "")
            if sip == ip:
                exact.add(name)
            elif sip.startswith(prefix):
                subnet.add(name)

if len(exact) == 1:
    print(exact.pop())
elif not exact and len(subnet) == 1:
    print(subnet.pop())
else:
    print("")
PY
}

main "$@"
