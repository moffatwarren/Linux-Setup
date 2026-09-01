#!/bin/bash

# Apply a wallpaper: hand it to the awww daemon, then point hyprlock's
# background at the same file so the lock screen matches the desktop.
#
# Everything that changes the wallpaper goes through here -- wallpaper-random.sh
# (SUPER+SHIFT+W) and the quickshell picker (WallpaperPicker.qml, SUPER+W) --
# so the transition flags and the hyprlock rewrite live in one place.

set -euo pipefail

WALLPAPER="${1:-}"

if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
  notify-send "Wallpaper Error" "Not a file: ${WALLPAPER:-<no argument given>}"
  exit 1
fi

awww img "$WALLPAPER" \
  --transition-type grow \
  --transition-pos 0.5,0.5 \
  --transition-duration 1 \
  --transition-fps 60

# hyprlock.conf has exactly one `path =` line, in its background block. The
# value is machine-local: install.sh's PRESERVE table captures and restores it
# (group `wallpaper`, in NO_PROMPT_GROUPS), so writing it here survives a deploy.
#
# `&` is the one character sed expands in a replacement, so escape it -- a
# filename containing one would otherwise duplicate the matched text.
ESCAPED=${WALLPAPER//&/\\&}
sed -i "s|^\([[:space:]]*\)path = .*|\1path = $ESCAPED|" "$HOME/.config/hypr/hyprlock.conf"
