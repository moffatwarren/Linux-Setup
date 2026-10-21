#!/usr/bin/env bash
#
# SUPER+S: select a region and annotate it in the bar's screenshot editor
# (quickshell/ScreenshotEditor.qml), in place of swappy.
#
#   (no args)        slurp a region, grim it, open it in the editor
#   --open <image>   open an existing image in the editor as if it had just
#                    been captured; "-" reads it from stdin
#                                                           (the clipboard's right-click)
#   --copy <png>     put an image on the clipboard          (the editor's Copy)
#   --save <png>     copy it into ~/Pictures/Screenshots    (the editor's Save)
#
# The editor renders the annotated image to a file and hands it back here, so
# the clipboard and the save directory are decided in one place, not in QML.

set -euo pipefail

RUNDIR="${XDG_RUNTIME_DIR:-/tmp}"
OUTDIR="$HOME/Pictures/Screenshots"

# Captures live under XDG_RUNTIME_DIR, which is wiped at logout. A unique name
# per capture, because the editor's Canvas caches a loaded image by URL and a
# reused path would show the previous screenshot. Earlier ones go first.
new_capture() {
  rm -f "$RUNDIR"/screenshot-capture-*.png "$RUNDIR"/screenshot-edited-*.png
  echo "$RUNDIR/screenshot-capture-$(date +%s%N).png"
}

# `qs ipc call` into a bar that is not running prints "Target not found" and
# still exits 0, so ask whether there is a bar first. Without one the capture
# is not lost: it goes straight to the clipboard, unannotated.
edit() {
  if pgrep -x quickshell >/dev/null; then
    qs ipc call screenshot open "$1"
  else
    wl-copy --type image/png < "$1"
    notify-send -a Screenshot "Screenshot copied" "The bar is not running, so it was not opened for editing"
  fi
}

case "${1:-}" in
  --copy)
    wl-copy --type image/png < "$2"
    # No -i: the theme's symbolic icons are invisible on the toast card.
    notify-send -a Screenshot "Screenshot copied" "The image is on the clipboard"
    exit 0
    ;;
  --save)
    mkdir -p "$OUTDIR"
    out="$OUTDIR/screenshot-$(date +%Y%m%d-%H%M%S).png"
    cp "$2" "$out"
    notify-send -a Screenshot "Screenshot saved" "$out"
    exit 0
    ;;
  --open)
    # Made the shape grim gives the editor: an opaque PNG. Transparency goes
    # onto white, as WarrenTool's editor does, because pixelate averages rgb
    # and ignores alpha -- a transparent area would mosaic to black. magick
    # also turns every format the clipboard can hold (webp, bmp, tiff...) into
    # one the Canvas can load, and [0] takes the first frame of a GIF or ICO,
    # which would otherwise be written as a numbered file per frame.
    img=$(new_capture)
    if ! magick "${2:?usage: $0 --open <image>|-}[0]" -background white -alpha remove -alpha off \
                "png:$img" 2>/dev/null; then
      rm -f "$img"
      notify-send -a Screenshot "Couldn't open the image" "It could not be read as an image"
      exit 1
    fi
    edit "$img"
    exit 0
    ;;
esac

# Escape out of slurp is a normal way to change your mind, not a failure.
region=$(slurp) || exit 0

img=$(new_capture)
grim -g "$region" "$img"
edit "$img"
