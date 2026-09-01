#!/bin/bash

# Function to get the current volume percentage
get_volume() {
  wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}'
}

# Function to check if the volume is muted
get_mute() {
  wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED && echo "yes" || echo "no"
}

# The icon NAME is the OSD's glyph selector: NotificationToasts.qml matches
# "muted" / "volume-low" / "volume-medium" in it and draws the matching Material
# Design glyph from the nerd font. The icon file is not rendered -- these are
# Adwaita *-symbolic SVGs, which GTK recoloured from a stylesheet but Qt would
# draw in the near-black fill baked into the file. Thresholds match
# AudioPill.qml's glyph choice, so the popup and the bar agree.
get_icon() {
  local volume=$1
  if [ "$volume" -eq 0 ]; then
    echo "audio-volume-muted-symbolic"
  elif [ "$volume" -lt 34 ]; then
    echo "audio-volume-low-symbolic"
  elif [ "$volume" -lt 67 ]; then
    echo "audio-volume-medium-symbolic"
  else
    echo "audio-volume-high-symbolic"
  fi
}

# Function to send the notification
send_notification() {
  volume=$(get_volume)
  mute=$(get_mute)

  # The 'x-canonical-private-synchronous' hint tells SwayNC to replace the existing notification
  if [ "$mute" == "yes" ]; then
    notify-send -a "volume" -h string:x-canonical-private-synchronous:audio-volume \
      -u low -i audio-volume-muted-symbolic "Volume Muted"
  else
    notify-send -a "volume" -h string:x-canonical-private-synchronous:audio-volume \
      -h int:value:"$volume" \
      -u low -i "$(get_icon "$volume")" "Volume: ${volume}%"
  fi
}

# Handle the arguments passed from Hyprland
case $1 in
up)
  # The '-l 1.0' flag limits the volume to 100%
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
  echo "Usage: $0 {up|down|mute}"
  exit 1
  ;;
esac
