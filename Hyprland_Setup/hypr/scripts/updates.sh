#!/usr/bin/env bash
# Pending package updates, for the quickshell update module (UpdatePill.qml
# and UpdateService.qml).
#
# Prints one JSON object of raw fields and leaves every bit of formatting to
# the QML, the way system-stats.sh and weather-forecast.sh do:
#
#   { "updated": 1764700000,
#     "repo": [ { "name": "linux", "old": "6.1.2-1", "new": "6.1.3-1" }, ... ],
#     "aur":  [ ... ] }
#
# THE ONE HARD RULE: never `pacman -Sy` to find out. A bare -Sy refreshes the
# sync databases without upgrading anything, which is how an Arch machine ends
# up in a partial-upgrade state -- the next single-package install pulls a
# library its dependents were not rebuilt against. `checkupdates`
# (pacman-contrib) exists precisely to avoid that: it copies the sync db to
# ${TMPDIR:-/tmp}/checkup-db-$UID and refreshes THAT, so /var/lib/pacman is
# never touched and no privilege is needed. It is the only correct way to ask
# this question, so it is a hard dependency, not a convenience.
#
# On any failure it prints nothing, so the module keeps its last good reading
# rather than showing a confidently wrong one -- the weather-forecast.sh rule.
# "Nothing pending" and "could not tell" are different answers and only one of
# them is printable.

set -uo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
CACHE="$CACHE_DIR/pending-updates.json"

# A repo sync is a real network request and the databases only move a few times
# a day, so most polls are served from here. The bar's timer uses the same six
# hours, which makes a tick that lands on a warm cache a `cat`.
MAX_AGE=$((6 * 3600))

MODE=poll
case "${1:-}" in
    # --force ignores the cache's age, for the pill's click-to-recheck.
    --force)      MAX_AGE=0 ;;
    # --revalidate is the cheap half: no network at all, just drop the entries
    # this machine has since installed. See revalidate() below.
    --revalidate) MODE=revalidate ;;
    --upgrade)    MODE=upgrade ;;
    "")           ;;
    *)            echo "usage: ${0##*/} [--force|--revalidate|--upgrade]" >&2; exit 1 ;;
esac

# Freshness is the cache's own `updated` field rather than its mtime, which is
# where this differs from weather-forecast.sh deliberately: --revalidate
# rewrites the file WITHOUT having synced anything, so an mtime would then
# claim a check that never happened and suppress the next real one.
cache_age() {
    local stamp
    [ -s "$CACHE" ] || return 1
    stamp=$(jq -r '.updated // empty' "$CACHE" 2>/dev/null) || return 1
    [ -n "$stamp" ] || return 1
    echo $(( $(date +%s) - stamp ))
}

fresh() {
    local age
    age=$(cache_age) || return 1
    [ "$age" -lt "$MAX_AGE" ]
}

# "name old -> new" (both checkupdates and paru -Qua print this) -> JSON array.
to_json() {
    awk 'NF >= 4 { printf "{\"name\":\"%s\",\"old\":\"%s\",\"new\":\"%s\"}\n", $1, $2, $4 }' \
        | jq -sc '.'
}

repo_updates() {
    local out status
    out=$(timeout 120 checkupdates --nocolor 2>/dev/null)
    status=$?
    # Verified against /usr/bin/checkupdates (v1.13.1): exit 2 with no output
    # means nothing is pending, exit 1 means it could not tell. Collapsing the
    # two -- which a bare `|| true` does -- is what turns a broken checker into
    # a permanent, confident "up to date".
    case "$status" in
        0|2) printf '%s\n' "$out" | to_json ;;
        *)   return 1 ;;
    esac
}

aur_updates() {
    # `paru -Qua` exits 1 with EMPTY stdout and EMPTY stderr when there simply
    # are no AUR updates -- verified on this machine -- so its exit code cannot
    # tell "none" from "the RPC failed". What settles it is that this only ever
    # runs after repo_updates() has already succeeded, and that needed a real
    # network sync: the repo check is the canary, so an empty answer here is a
    # genuine "none" rather than a silent failure.
    #
    # No --devel: it would fetch every -git package's upstream ref on each poll.
    # Those show up on the next real rebuild instead.
    timeout 90 paru -Qua --color never 2>/dev/null | to_json
}

# The no-network half. Every cached entry says "you have `old`, `new` is out";
# if the installed version is no longer `old` then the entry is stale whatever
# it is now, so one `pacman -Q` over the pending names is enough to drop the
# packages a manual `paru -Syu` in a terminal has just upgraded. Anything more
# subtle needs a sync, which is what the six-hourly poll is for.
revalidate() {
    local names installed
    [ -s "$CACHE" ] || return 1
    names=$(jq -r '(.repo + .aur)[].name' "$CACHE" 2>/dev/null) || return 1
    if [ -z "$names" ]; then
        cat "$CACHE"
        return 0
    fi
    # A name pacman no longer knows (the package was removed rather than
    # upgraded) just prints an error we ignore; it drops out of $have below and
    # so drops out of the list, which is the right answer for it too.
    installed=$(pacman -Q $names 2>/dev/null)

    jq -c --arg inst "$installed" '
        ($inst
         | split("\n")
         | map(select(length > 0) | split(" ") | { key: .[0], value: .[1] })
         | from_entries) as $have
        | .repo |= map(select(($have[.name] // "") == .old))
        | .aur  |= map(select(($have[.name] // "") == .old))
    ' "$CACHE"
}

case "$MODE" in
    revalidate)
        out=$(revalidate) || exit 0
        mkdir -p "$CACHE_DIR"
        printf '%s\n' "$out" > "$CACHE"
        printf '%s\n' "$out"
        exit 0
        ;;
    upgrade)
        trap 'command -v qs >/dev/null 2>&1 && qs ipc call updates refresh >/dev/null 2>&1 || true' EXIT
        paru -Syu
        exit_code=$?
        echo
        if command -v qs >/dev/null 2>&1; then
            qs ipc call updates refresh >/dev/null 2>&1 || true
        fi
        read -r -n1 -p "Press any key to close."
        exit $exit_code
        ;;
esac

if fresh; then
    cat "$CACHE"
    exit 0
fi

repo=$(repo_updates) || { [ -s "$CACHE" ] && cat "$CACHE"; exit 0; }
aur=$(aur_updates)
[ -n "$aur" ] || aur='[]'

out=$(jq -nc --argjson repo "$repo" --argjson aur "$aur" --arg now "$(date +%s)" \
        '{ updated: ($now | tonumber), repo: $repo, aur: $aur }') || exit 0

mkdir -p "$CACHE_DIR"
printf '%s\n' "$out" > "$CACHE"
printf '%s\n' "$out"
