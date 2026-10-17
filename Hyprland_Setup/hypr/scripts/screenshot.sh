#!/usr/bin/env bash
#
# SUPER+S: select a region and annotate it in the bar's screenshot editor
# (quickshell/ScreenshotEditor.qml), in place of swappy.
#
#   (no args)        slurp a region, grim it, open it in the editor
#   --copy <png>     put an image on the clipboard          (the editor's Copy)
#   --save <png>     copy it into ~/Pictures/Screenshots    (the editor's Save)
#
# The editor renders the annotated image to a file and hands it back here, so
# the clipboard and the save directory are decided in one place, not in QML.

set -euo pipefail

RUNDIR="${XDG_RUNTIME_DIR:-/tmp}"
OUTDIR="$HOME/Pictures/Screenshots"

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
esac

# Escape out of slurp is a normal way to change your mind, not a failure.
region=$(slurp) || exit 0

# Captures live under XDG_RUNTIME_DIR, which is wiped at logout. A unique name
# per capture, because the editor's Canvas caches a loaded image by URL and a
# reused path would show the previous screenshot. Earlier ones go first.
rm -f "$RUNDIR"/screenshot-capture-*.png "$RUNDIR"/screenshot-edited-*.png
img="$RUNDIR/screenshot-capture-$(date +%s%N).png"
grim -g "$region" "$img"

# `qs ipc call` into a bar that is not running prints "Target not found" and
# still exits 0, so ask whether there is a bar first. Without one the capture
# is not lost: it goes straight to the clipboard, unannotated.
if pgrep -x quickshell >/dev/null; then
  qs ipc call screenshot open "$img"
else
  wl-copy --type image/png < "$img"
  notify-send -a Screenshot "Screenshot copied" "The bar is not running, so it was not opened for editing"
fi
