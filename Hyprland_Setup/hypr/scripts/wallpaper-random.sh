#!/bin/bash

# 1. Define where your wallpapers are stored
WALLPAPER_DIR="$HOME/Pictures/wallpapers"

# 2. Verify the directory exists
if [ ! -d "$WALLPAPER_DIR" ]; then
    notify-send "Wallpaper Error" "Directory does not exist: $WALLPAPER_DIR"
    exit 1
fi

# 3. Find all images and pick one at random
# -type f ensures we only get files (no sub-folders)
# shuf -n 1 shuffles the list and picks the top 1 result
RANDOM_PIC=$(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" \) | shuf -n 1)

# 4. Check if we actually found an image
if [ -z "$RANDOM_PIC" ]; then
    notify-send "Wallpaper Error" "No images found in $WALLPAPER_DIR"
    exit 1
fi

# 5. Apply it with awww
# Tip: "--transition-type any" tells swww to pick a random animation effect!
awww img "$RANDOM_PIC" --transition-type grow --transition-pos 0.5,0.5 --transition-fps 60 --transition-duration 1
sed -i "s|path = .*|path = $RANDOM_PIC|g" "$HOME/.config/hypr/hyprlock.conf"
