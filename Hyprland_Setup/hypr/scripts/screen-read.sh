#!/bin/bash
# SUPER+ALT+S: select a region and copy what it says. A QR code in the region
# wins -- its payload (usually a URL) is copied -- and otherwise the region is
# OCRed, which is all this key used to do.
#
# With an argument it reads that image instead of asking for a region, which
# is how to test the decoding without a hand on the mouse.

set -euo pipefail

if [ $# -gt 0 ]; then
  img="$1"
else
  # Escape out of slurp is a normal way to change your mind, not a failure.
  region=$(slurp) || exit 0
  img=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/screen-read-XXXXXX.png")
  trap 'rm -f "$img"' EXIT
  grim -g "$region" "$img"
fi

# The bar draws a notification body as StyledText, so the copied text has to be
# escaped or a URL's "&lt=" and any "<" in OCRed code are eaten as markup, and
# line breaks need a <br> to survive. Capped, since the card shows four lines.
announce() {
  local body=${2:0:400}
  body=${body//&/&amp;}
  body=${body//</&lt;}
  body=${body//>/&gt;}
  body=${body//$'\n'/<br>}
  # No -i: the theme's symbolic icons are invisible on the toast card.
  notify-send -a "$1" "$1 copied" "$body"
}

# Only the QR symbology is enabled, so a block of text or a table edge cannot
# be misread as a 1D barcode and steal the OCR path. zbarimg exits 4 for "no
# code found", hence the || true: the output being empty is the answer.
scan() { zbarimg -q --raw -Sdisable -Sqrcode.enable "$1" 2>/dev/null || true; }

qr=$(scan "$img")
# zbar does not read a light-on-dark code at all (measured: exit 4 on a negated
# QR), and dark-theme pages draw them that way, so a miss is retried inverted.
# magick is a hard dependency of zbar, so it is there whenever zbarimg is.
[ -n "$qr" ] || qr=$(magick "$img" -negate png:- 2>/dev/null | scan png:-)

if [ -n "$qr" ]; then
  # printf rather than echo: no trailing newline, so a URL pastes clean.
  printf '%s' "$qr" | wl-copy
  announce "QR code" "$qr"
  exit 0
fi

text=$(tesseract "$img" stdout 2>/dev/null || true)
# An empty read is not copied, so a miss does not wipe the clipboard.
[ -n "$text" ] || exit 0
printf '%s\n' "$text" | wl-copy
announce "Text" "$text"
