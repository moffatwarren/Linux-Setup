#!/bin/bash
#
# The XF86AudioRaise/Lower/Mute keys: change the level and draw the OSD.
#
# get_volume / get_mute / get_default_sink / icon_key / icon_name are shared
# with audio-output-toggle.sh -- see audio-lib.sh for why they are not copied
# into both any more.

set -uo pipefail

source "$(dirname "$(readlink -f "$0")")/audio-lib.sh"

# The x-canonical-private-synchronous hint is what marks this as an OSD rather
# than a message: NotificationService.qml replaces the popup carrying the same
# tag instead of stacking one (so holding the key leaves a single card counting
# up), and keeps the reading out of the notification list entirely -- a volume
# tap is not something to come back to. int:value is the 0-100 the card draws
# as a progress bar; neither hint has a dedicated property on Notification, so
# both are listed in the server's extraHints.
send_notification() {
  local volume mute
  volume=$(get_volume)
  mute=$(get_mute)

  if [ "$mute" = "yes" ]; then
    # No int:value: there is no level to report while muted, and a bar sitting
    # at the old number under the word "Muted" reads as a contradiction.
    notify-send -a "volume" -h string:x-canonical-private-synchronous:audio-volume \
      -u low -i "$(icon_name "$volume" yes)" "Volume Muted"
  else
    notify-send -a "volume" -h string:x-canonical-private-synchronous:audio-volume \
      -h int:value:"$volume" \
      -u low -i "$(icon_name "$volume" no "$(get_default_sink)")" "Volume: ${volume}%"
  fi
}

case "${1:-}" in
up)
  # -l 1.0 caps the level at 100%.
  wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 1%+
  send_notification
  ;;
down)
  wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-
  send_notification
  ;;
mute)
  wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
  send_notification
  ;;
*)
  echo "Usage: ${0##*/} {up|down|mute}" >&2
  exit 1
  ;;
esac
