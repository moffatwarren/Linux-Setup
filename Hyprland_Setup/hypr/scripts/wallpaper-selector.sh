#!/bin/bash

# 1. Define where your wallpapers are stored
WALLPAPER_DIR="$HOME/Pictures/wallpapers"

# 2. Check if the directory exists
if [ ! -d "$WALLPAPER_DIR" ]; then
    notify-send "Error" "Wallpaper directory not found: $WALLPAPER_DIR"
    exit 1
fi

# 3. Move into the directory to make listing files easier
cd "$WALLPAPER_DIR" || exit

# 4. Build the Rofi list with image paths attached
# The magic syntax "\0icon\x1f" tells Rofi to use the following path as an image preview
FILE_LIST=""
for file in *; do
    # Only process actual files (ignore sub-folders)
    if [ -f "$file" ]; then
        FILE_LIST+="${file}\0icon\x1f${WALLPAPER_DIR}/${file}\n"
    fi
done

# 5. Pipe the list into Rofi
# -show-icons enables the previews
# -theme-str injects CSS-like rules to create a 4-column grid and make the icons large
SELECTED=$(echo -e "$FILE_LIST" | rofi -dmenu -i -p "Choose Wallpaper:" \
    -show-icons \
    -theme-str 'window { width: 60%; }' \
    -theme-str 'listview { columns: 4; lines: 3; }' \
    -theme-str 'element-icon { size: 8em; }' \
    -theme-str 'element-text { horizontal-align: 0.5; }' \
    -theme-str 'element { orientation: vertical; }')

# 6. If you selected something, apply it
if [ -n "$SELECTED" ]; then
    WALLPAPER_PATH="$WALLPAPER_DIR/$SELECTED"

    # Apply with awww (using a 1-second duration)
    awww img "$WALLPAPER_PATH" --transition-type grow --transition-pos 0.5,0.5 --transition-duration 1 --transition-fps 60
    sed -i "s|path = .*|path = $WALLPAPER_PATH|g" "$HOME/.config/hypr/hyprlock.conf"
fi
