#!/usr/bin/env bash
#
# SUPER+E: open the default file explorer, whichever that is -- chosen in the
# SUPER+D menu, so nothing in this repo names one.
#
# Which one is not worked out here. `default-apps.sh --resolve filemanager` is
# the same resolver the menu's "Default:" badge reads, so the badge and this key
# cannot disagree. It matters more for folders than for any other category: with
# no explicit default GIO resolves inode/directory to VSCodium on this machine,
# because an IDE declares it can open a folder -- the resolver only trusts GIO
# when GIO names an actual file explorer.
#
# `gio launch` expands the entry's own Exec= (field codes, Terminal= for yazi or
# ranger, DBusActivatable for nautilus, flatpak), and $HOME is passed so every
# file explorer opens in the same place rather than in whatever directory it was
# spawned from.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -a "File Explorer" "No file explorer" "$1" 2>/dev/null || true
    echo "launch-file-manager: $1" >&2
    exit 1
}

path=$(bash "$SCRIPT_DIR/default-apps.sh" --resolve filemanager 2>/dev/null || true)
[ -n "$path" ] && [ -f "$path" ] ||
    die "no installed application is a file explorer -- install one, then pick it with SUPER+D"

if command -v gio >/dev/null 2>&1; then
    exec gio launch "$path" "$HOME"
fi
if command -v gtk-launch >/dev/null 2>&1; then
    id="${path##*/}"
    exec gtk-launch "${id%.desktop}" "$HOME"
fi
die "neither gio nor gtk-launch is available to start ${path##*/}"
