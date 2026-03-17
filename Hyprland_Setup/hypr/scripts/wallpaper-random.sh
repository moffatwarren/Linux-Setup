#!/bin/bash

# Define the directory containing your wallpapers
WALLPAPER_DIR="$HOME/Pictures/wallpapers"

# Get a random wallpaper file
WALLPAPER=$(find "$WALLPAPER_DIR" -type f | shuf -n 1)

# Check if a wallpaper was found
if [ -z "$WALLPAPER" ]; then
    echo "Error: No wallpaper file found in $WALLPAPER_DIR"
    exit 1
fi

# Use hyprctl to dynamically set the new wallpaper

# 1. Preload the new wallpaper
hyprctl hyprpaper preload "$WALLPAPER"

# 2. Set the wallpaper for all monitors (the empty monitor argument acts as a wildcard)
# You can specify a monitor name (e.g., "DP-1") instead of the comma for a specific monitor
hyprctl hyprpaper wallpaper ",$WALLPAPER"

sleep 1

# 3. Unload unused wallpapers (optional, helps manage RAM usage)
hyprctl hyprpaper unload unused

sed -i "s|path = .*|path = $WALLPAPER|g" "$HOME/.config/hypr/hyprlock.conf"
sed -i "s|path = .*|path = $WALLPAPER|g" "$HOME/.config/hypr/hyprpaper.conf"

echo "Wallpaper changed to $WALLPAPER"
