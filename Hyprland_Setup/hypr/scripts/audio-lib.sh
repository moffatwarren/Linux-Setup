#!/bin/bash
#
# Shared audio helpers. Sourced by volume-notify.sh (the XF86Audio* keys) and
# audio-output-toggle.sh (SUPER+O) -- the two scripts that have to agree with
# the bar about which output this is and what glyph stands for it.
#
# It exists because they had already drifted. Both carried their own copy of
# icon_key(), and neither of them checked `displayport` where
# AudioService.defaultIconKey does -- so a DisplayPort sink drew the display
# glyph on the pill and a volume glyph in the OSD beside it, which is exactly
# the disagreement passing the icon name through was meant to prevent. Two
# copies of one inference is one too many; there is a third in QML and that one
# cannot be helped, so this is the floor.
#
# Sourced, not executed: `source "$(dirname "$(readlink -f "$0")")/audio-lib.sh"`,
# the same way wallpaper-random.sh reaches wallpaper-set.sh.

# Written by the bar (AudioService.qml), read here and never written back:
#   { "outputs": [ { "name": …, "description": …, "enabled": true, "icon": … } ] }
STATE="$HOME/.cache/quickshell-audio.json"

get_volume() {
  wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}'
}

get_mute() {
  wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED && echo "yes" || echo "no"
}

get_default_sink() {
  local name
  name=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk -F'"' '/node.name =/{print $2; exit}')
  [ -n "$name" ] || name=$(pactl get-default-sink 2>/dev/null)
  printf '%s\n' "$name"
}

# The glyph the bar's audio menu has for this sink, or the inference it falls
# back to when nothing has been picked. KEEP THIS IN STEP WITH
# AudioService.defaultIconKey in quickshell/AudioService.qml -- bluez is a
# prefix check there and here, hdmi/displayport are substring checks in both.
# Headphones-versus-speakers is deliberately not guessed: that is the one
# distinction a sink name cannot settle, and the whole reason the picker exists.
icon_key() {
  local name=${1:-} key=""
  if [ -r "$STATE" ]; then
    key=$(jq -r --arg n "$name" \
          '(.outputs // [])[] | select(.name == $n) | .icon // empty' \
          "$STATE" 2>/dev/null | head -n 1)
  fi
  if [ -n "$key" ]; then
    printf '%s\n' "$key"
  elif [ "${name#bluez}" != "$name" ]; then
    printf 'bluetooth\n'
  elif [ "${name#*hdmi}" != "$name" ] || [ "${name#*displayport}" != "$name" ]; then
    printf 'display\n'
  else
    printf 'volume\n'
  fi
}

# The icon NAME for a notification's -i flag. Qt never renders the SVG behind
# it -- NotificationToasts.qml matches "muted" / "volume-low" / "volume-medium"
# / "headphone" / "speaker" / … in the name and draws its own Material Design
# glyph -- so this only has to be a key both sides agree on.
#
#   $1 volume 0-100   $2 muted (yes/no)   $3 sink name
icon_name() {
  local volume=${1:-} muted=${2:-no} sink=${3:-} key
  # An unreadable level is not silence: fall through to the full glyph rather
  # than claiming muted. Both callers did this by accident before, by guarding
  # every numeric test on `[ -n "$VOL" ]` and landing in the else.
  case $volume in ''|*[!0-9]*) volume=100 ;; esac

  if [ "$muted" = "yes" ]; then
    printf 'audio-volume-muted-symbolic\n'
    return 0
  fi

  key=$(icon_key "$sink")
  if [ "$key" != "volume" ]; then
    printf 'audio-%s-symbolic\n' "$key"
  elif [ "$volume" -eq 0 ]; then
    printf 'audio-volume-muted-symbolic\n'
  elif [ "$volume" -lt 34 ]; then
    printf 'audio-volume-low-symbolic\n'
  elif [ "$volume" -lt 67 ]; then
    printf 'audio-volume-medium-symbolic\n'
  else
    printf 'audio-volume-high-symbolic\n'
  fi
}
