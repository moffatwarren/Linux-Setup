#!/bin/bash

# SUPER+SHIFT+W: pick a random wallpaper out of the wallpaper directory.
# Applying it is wallpaper-set.sh's job.

set -euo pipefail

WALLPAPER_DIR="$HOME/Pictures/wallpapers"

if [ ! -d "$WALLPAPER_DIR" ]; then
  notify-send "Wallpaper Error" "Directory does not exist: $WALLPAPER_DIR"
  exit 1
fi

RANDOM_PIC=$(find "$WALLPAPER_DIR" -type f \
  \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
     -o -iname "*.gif" -o -iname "*.webp" -o -iname "*.bmp" \) | shuf -n 1)

if [ -z "$RANDOM_PIC" ]; then
  notify-send "Wallpaper Error" "No images found in $WALLPAPER_DIR"
  exit 1
fi

exec "$(dirname "$(readlink -f "$0")")/wallpaper-set.sh" "$RANDOM_PIC"
