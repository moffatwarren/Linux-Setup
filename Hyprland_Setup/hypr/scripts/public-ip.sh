#!/usr/bin/env bash
# This machine's public IP, for the network module's hover panel.
#
# Prints one bare IPv4 address, or nothing at all -- on a failure the module
# keeps its last good reading rather than showing a confidently wrong one, the
# same contract weather-forecast.sh has.
#
# Answering it means asking somebody else's server, so the answer is cached for
# ten minutes and the bar only asks while the panel is actually open. --force
# ignores the cache, which is what a change of link does: the address the old
# connection had says nothing about the new one.

set -uo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/public-ip"
MAX_AGE=$((10 * 60))
FORCED=0

case "${1:-}" in
    --force) MAX_AGE=0; FORCED=1 ;;   # fresh() compares age -lt 0, never true
esac

fresh() {
    local age
    [ -s "$CACHE" ] || return 1
    age=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$MAX_AGE" ]
}

# Two providers, because either one can be down and a blank row is
# indistinguishable from "you have no public address". Both answer with a bare
# address and neither needs a key.
#
# -4 because the panel's other address row is the interface's IPv4, and one row
# reading 203.0.113.5 beside another reading a v6 address looks like a
# contradiction rather than two facts.
fetch() {
    local url ip
    for url in https://icanhazip.com https://api.ipify.org; do
        ip=$(curl -4 -s --max-time 5 "$url" | tr -d '[:space:]')
        # Checked by shape, not by curl's exit status: a captive portal answers
        # every request with a login page, successfully.
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            printf '%s\n' "$ip"
            return 0
        fi
    done
    return 1
}

if fresh; then
    cat "$CACHE"
    exit 0
fi

if ip=$(fetch); then
    # A fresh account may not have ~/.cache yet, as every other caching script
    # here assumes it might not.
    mkdir -p "$(dirname "$CACHE")"
    printf '%s\n' "$ip" > "$CACHE"
    printf '%s\n' "$ip"
elif [ "$FORCED" -eq 0 ] && [ -s "$CACHE" ]; then
    # Stale beats blank: an address that was right ten minutes ago is very
    # likely still right. Not after --force, though -- that is only ever asked
    # because the link changed, and the old link's address is then the one
    # answer that is definitely wrong.
    cat "$CACHE"
fi
