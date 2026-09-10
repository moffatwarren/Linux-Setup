#!/bin/bash

# Function to get the current volume percentage
get_volume() {
  wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}'
}

# Function to check if the volume is muted
get_mute() {
  wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED && echo "yes" || echo "no"
}

get_default_sink() {
  local name
  name=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '/node.name =/{print $2; exit}')
  if [ -z "$name" ]; then
    name=$(pactl get-default-sink 2>/dev/null)
  fi
  printf '%s\n' "$name"
}

STATE="$HOME/.cache/quickshell-audio.json"

icon_key() {
  local key=""
  if [ -r "$STATE" ]; then
    key=$(jq -r --arg n "$1" \
          '(.outputs // [])[] | select(.name == $n) | .icon // empty' \
          "$STATE" 2>/dev/null | head -n 1)
  fi
  if [ -n "$key" ]; then
    printf '%s\n' "$key"
  elif [ "${1#bluez}" != "$1" ]; then
    printf 'bluetooth\n'
  elif [ "${1#*hdmi}" != "$1" ]; then
    printf 'display\n'
  else
    printf 'volume\n'
  fi
}

# The icon NAME is the OSD's glyph selector: NotificationToasts.qml matches
# "muted" / "volume-low" / "volume-medium" / "headphone" / "speaker" / etc. in it
# and draws the matching Material Design glyph from the nerd font. The icon file
# is not rendered -- these are Adwaita *-symbolic SVGs, which GTK recoloured from
# a stylesheet but Qt would draw in the near-black fill baked into the file.
# Thresholds and sink icon lookups match AudioPill.qml's glyph choice, so the
# popup and the bar agree.
get_icon() {
  local volume=$1
  local current
  current=$(get_default_sink)
  local key
  key=$(icon_key "$current")

  if [ "$key" != "volume" ]; then
    echo "audio-${key}-symbolic"
  elif [ "$volume" -eq 0 ]; then
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
