#!/bin/bash
# Thumbnail cache for the SUPER+W picker (quickshell/WallpaperPicker.qml).
#
# The picker used to decode every tile straight from ~/Pictures/wallpapers,
# where most of the files are 15-20 MB 4K PNGs. PNG has no reduced-size decode,
# so `sourceSize` did not help -- every tile was a full decompress, one at a
# time on Qt's single pixmap reader thread, and redone on nearly every opening
# because Qt's unreferenced-pixmap cache is far too small to keep them. This
# writes a tile-sized JPEG per wallpaper once, and the picker reads those.
#
#   (no args)    bring the cache up to date; prints how many thumbnails it
#                wrote or removed, so the picker can tell "nothing changed"
#                from "reload the tiles"
#
# A thumbnail is <cache>/<filename>.jpg, regenerated when the wallpaper is
# newer than it, and removed when the wallpaper is gone. Each is written to a
# temporary name and renamed into place, so the picker can never read half of
# one. Safe to run while another run is in progress -- the worst case is one
# image converted twice.
set -uo pipefail

SRC_DIR="$HOME/Pictures/wallpapers"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/wallpaper-thumbs"
# Enough to cover the selected tile (510x400 in WallpaperPicker.qml) at 2x,
# under PreserveAspectCrop -- hence `^`, which makes these minimums, not maxima.
SIZE="1020x800^"

[ -d "$SRC_DIR" ] || { echo 0; exit 0; }
mkdir -p "$CACHE_DIR"

shopt -s nullglob nocaseglob
changed=0
todo=()
for src in "$SRC_DIR"/*.{jpg,jpeg,png,gif,webp,bmp}; do
    thumb="$CACHE_DIR/${src##*/}.jpg"
    [ "$thumb" -nt "$src" ] || todo+=("$src")
done
shopt -u nocaseglob

# One magick per image, as many at once as there are cores. `[0]` takes the
# first frame of a gif; -thumbnail strips metadata as it scales.
if [ ${#todo[@]} -gt 0 ]; then
    printf '%s\0' "${todo[@]}" | nice -n 10 xargs -0 -P "$(nproc)" -I{} sh -c '
        src=$1; dir=$2; size=$3
        thumb="$dir/${src##*/}.jpg"
        tmp="$thumb.tmp.$$"
        if magick "$src[0]" -auto-orient -thumbnail "$size" -quality 85 "jpg:$tmp" 2>/dev/null; then
            mv -f "$tmp" "$thumb"
        else
            rm -f "$tmp"
        fi
    ' _ {} "$CACHE_DIR" "$SIZE"
    changed=$((changed + ${#todo[@]}))
fi

# Prune thumbnails whose wallpaper has gone. A temp file is only removed once
# it is old enough that no run can still be writing it -- it is a killed one's.
for thumb in "$CACHE_DIR"/*.jpg; do
    name=${thumb##*/}
    [ -e "$SRC_DIR/${name%.jpg}" ] || { rm -f "$thumb"; changed=$((changed + 1)); }
done
find "$CACHE_DIR" -maxdepth 1 -name '*.tmp.*' -mmin +10 -delete 2>/dev/null

echo "$changed"
