#!/usr/bin/env bash
#
# Launches whatever browser is currently the default -- SUPER+B, SUPER+G and
# CalendarPopup's footer all come through here, so nothing in this repo names a
# browser.
#
#   launch-browser.sh                 open the browser
#   launch-browser.sh <url>           open a URL in it
#   launch-browser.sh --app=<url>     open a URL as a standalone app window
#
# The first two go through `gio launch`, which expands the .desktop file's own
# Exec= correctly for every packaging shape (env wrappers, flatpak, Terminal=,
# DBusActivatable). Only --app= builds its own argv, because injecting a *flag*
# is the one thing no launcher will do -- which is why an earlier version using
# `gtk-launch` failed: it treats trailing arguments as files, never as flags.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

die() {
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -a "Browser" "No default browser" "$1" 2>/dev/null || true
    echo "launch-browser: $1" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Which .desktop is the default browser. Four sources, most authoritative
# first; no hardcoded answer -- printing nothing rather than guessing is what
# public-ip.sh and `pia.sh --service` already do.
# ---------------------------------------------------------------------------
default_browser_id() {
    local id=""

    if command -v xdg-settings >/dev/null 2>&1; then
        id=$(xdg-settings get default-web-browser 2>/dev/null || true)
    fi

    if [ -z "$id" ] && [ -f "$CONFIG_HOME/mimeapps.list" ]; then
        # sed quits at the first hit rather than piping to `head`, which would
        # SIGPIPE the producer and, under pipefail, report exit 141 for a
        # lookup that succeeded (the clipboard-history.sh trap).
        id=$(sed -nE '/^x-scheme-handler\/https=/{s/^[^=]*=([^;]+).*/\1/;p;q}' \
             "$CONFIG_HOME/mimeapps.list" || true)
    fi

    if [ -z "$id" ] && command -v gio >/dev/null 2>&1; then
        id=$(gio mime x-scheme-handler/https 2>/dev/null |
             sed -nE '/^Default application/{s/.*:[[:space:]]*//;p;q}' || true)
    fi

    # Last resort: the first entry that declares it can open https. Same scan
    # the SUPER+D menu lists from, so the two can never disagree about what
    # counts as a browser.
    if [ -z "$id" ] && [ -x "$SCRIPT_DIR/default-apps.sh" ]; then
        id=$("$SCRIPT_DIR/default-apps.sh" --list 2>/dev/null |
             python3 -c 'import json,sys
try:
    apps = json.load(sys.stdin)["browser"]["apps"]
    print(apps[0]["id"] if apps else "")
except Exception:
    print("")' || true)
    fi

    [ -n "$id" ] || return 1
    [[ "$id" == *.desktop ]] || id="${id}.desktop"
    printf '%s\n' "$id"
}

# Where that .desktop actually lives. The XDG search path in spec order, plus
# the flatpak exports that are missing from XDG_DATA_DIRS in a bare Hyprland
# session. XDG_DATA_DIRS *replaces* the /usr defaults when it is set -- hard-
# coding them alongside makes a sandbox (or a test) silently reach the system
# copy instead of the one it was pointed at.
desktop_path() {
    local id="$1" data_home data_dirs dir
    data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    data_dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

    local dirs=("$data_home/applications")
    local IFS=:
    for dir in $data_dirs; do
        [ -n "$dir" ] && dirs+=("$dir/applications")
    done
    unset IFS
    dirs+=("$data_home/flatpak/exports/share/applications"
           /var/lib/flatpak/exports/share/applications)

    for dir in "${dirs[@]}"; do
        [ -f "$dir/$id" ] && { printf '%s\n' "$dir/$id"; return 0; }
    done
    return 1
}

# One key's value out of the [Desktop Entry] section.
entry_key() {
    sed -nE "/^\\[Desktop Entry\\]/,/^\\[/{/^$2=/{s/^$2=//;p;q}}" "$1" || true
}

# ---------------------------------------------------------------------------
# Build the argv from Exec=, keeping any `env VAR=...` or `flatpak run ...`
# prefix -- those are load-bearing, and taking only the first token (which an
# earlier version did) yields `env` or `flatpak` as the "binary" and then
# silently runs `env https://...`.
# ---------------------------------------------------------------------------
exec_argv() {
    local exec_line="$1" stripped
    # %% is a literal percent; park it before stripping the field codes.
    stripped="${exec_line//%%/$'\x01'}"
    stripped=$(printf '%s' "$stripped" | sed -E 's/%[uUfFickdDnNvm]//g')
    stripped="${stripped//$'\x01'/%}"
    # Desktop Exec quoting is sh-compatible, so let the shell do the splitting;
    # this is what handles a quoted path with a space in it.
    eval "argv=( $stripped )"
}

# The engine is read from the whole entry -- Exec, id, StartupWMClass, TryExec
# -- not from argv[0], so an env- or flatpak-wrapped browser is still placed.
detect_engine() {
    local blob="${1,,}"
    case "$blob" in
        *chrom*|*brave*|*edge*|*vivaldi*|*opera*|*thorium*|*ungoogled*|*yandex*|*whale*)
            echo chromium ;;
        *firefox*|*librewolf*|*waterfox*|*floorp*|*zen*|*icecat*|*palemoon*|*tor-browser*|*mullvad-browser*)
            echo gecko ;;
        *) echo unknown ;;
    esac
}

# gio expands the Exec correctly for every packaging shape; only reach past it
# when it is genuinely missing.
launch_plain() {
    local path="$1" id="$2"
    shift 2
    if command -v gio >/dev/null 2>&1; then
        exec gio launch "$path" "$@"
    elif command -v gtk-launch >/dev/null 2>&1; then
        exec gtk-launch "${id%.desktop}" "$@"
    fi
    local argv=()
    exec_argv "$(entry_key "$path" Exec)"
    [ ${#argv[@]} -gt 0 ] || die "$id has no Exec= line"
    exec "${argv[@]}" "$@"
}

# ---------------------------------------------------------------------------

id=$(default_browser_id) || die "nothing is registered for https:// -- set one with SUPER+D"
path=$(desktop_path "$id") || die "$id is the default browser but no such .desktop exists"

arg="${1:-}"

if [ -z "$arg" ]; then
    launch_plain "$path" "$id"
fi

if [[ "$arg" != --app=* ]]; then
    launch_plain "$path" "$id" "$arg"
fi

url="${arg#--app=}"
exec_line=$(entry_key "$path" Exec)
[ -n "$exec_line" ] || die "$id has no Exec= line"

engine=$(detect_engine "$exec_line $id $(entry_key "$path" StartupWMClass) $(entry_key "$path" TryExec)")

argv=()
exec_argv "$exec_line"
[ ${#argv[@]} -gt 0 ] || die "$id has an empty Exec= line"

case "$engine" in
    chromium) exec "${argv[@]}" "--app=$url" ;;
    # Gecko has no standalone-app mode; a new window is the honest equivalent.
    gecko)    exec "${argv[@]}" --new-window "$url" ;;
    *)        launch_plain "$path" "$id" "$url" ;;
esac
