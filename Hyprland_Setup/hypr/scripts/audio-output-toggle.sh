#!/bin/bash
#
# SUPER+O -- step to the next audio output.
#
# Everything machine-specific about audio now lives in the bar's audio menu
# (left-click the audio pill), which AudioService.qml persists to the state file
# below. This script reads it and never writes it:
#
#   { "outputs": [ { "name": …, "description": …, "enabled": true, "icon": … } ] }
#
#   enabled -- whether SUPER+O steps to this output. No record counts as
#              enabled, so a machine that has never opened the menu, or a sink
#              plugged in for the first time, still cycles.
#   icon    -- which glyph the bar draws for it, and so which icon name the OSD
#              below is given. NotificationToasts.qml matches on that name to
#              pick its own glyph, so the popup and the bar agree.
#
# This file used to declare BUILT_IN_SINK / HEADPHONE_SINK / SPEAKER_SINK /
# BLUETOOTH_SINK, because a sink's role cannot be inferred from its name and
# something had to say which was which. That made the answer a shell edit, one
# of only two role names, and a PRESERVE entry in install.sh to survive a deploy.
# The menu asks instead, and remembers -- so there is nothing hardware-specific
# left in here, and nothing for install.sh to preserve.

STATE="$HOME/.cache/quickshell-audio.json"

get_volume() {
  wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}'
}

# Sink names in pactl's index order, which is the PipeWire node id -- the same
# order AudioMenu lists them in, so the menu reads top-to-bottom as the cycle.
#
# The tab-separated form is the fallback because `-f json` needs PulseAudio 16
# (2022) and this is the one call the whole script cannot do without: an empty
# list makes SUPER+O exit silently, which reads as a dead keybind rather than as
# a missing feature. Sink names never contain whitespace, so cut -f2 is exact.
present_sinks() {
  local out
  out=$(pactl -f json list short sinks 2>/dev/null | jq -r '.[].name' 2>/dev/null)
  if [ -z "$out" ]; then
    out=$(pactl list short sinks 2>/dev/null | cut -f2)
  fi
  # No sinks at all: print nothing rather than one empty line, which mapfile
  # would read as a single nameless sink and carry all the way to a
  # `pactl set-default-sink ""`.
  [ -n "$out" ] || return 0
  # A name is unique in the menu but not in PipeWire: replugging a monitor mid
  # session leaves WirePlumber's old HDMI sink node behind beside the new one,
  # and pactl lists every one of them. Duplicates are worse than cosmetic here
  # -- the cycle below matches the current sink by name, so it would step from
  # the first copy to the second, set the default to the name it already has,
  # and leave SUPER+O stuck on that output for ever. awk keeps the first.
  printf '%s\n' "$out" | awk '!seen[$0]++'
}

# Only outputs explicitly switched off in the menu. Everything else is in.
disabled_sinks() {
  [ -r "$STATE" ] || return 0
  jq -r '(.outputs // []) | map(select(.enabled == false) | .name) | .[]' "$STATE" 2>/dev/null
}

mapfile -t ALL < <(present_sinks)
[ ${#ALL[@]} -gt 0 ] || exit 0

DISABLED=$(disabled_sinks)

# The menu's icon choice for a sink, or nothing when it has never been set --
# in which case the bar infers one (AudioService.defaultIconKey) and so does the
# `volume` fallback below, which is the same answer.
icon_key() {
  local key=""
  if [ -r "$STATE" ]; then
    key=$(jq -r --arg n "$1" \
          'first((.outputs // [])[] | select(.name == $n) | .icon) // empty' \
          "$STATE" 2>/dev/null)
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

CANDIDATES=()
for name in "${ALL[@]}"; do
  printf '%s\n' "$DISABLED" | grep -Fxq -- "$name" && continue
  CANDIDATES+=("$name")
done

# Every output switched off is a configuration you can reach from the menu, and
# a dead SUPER+O is a worse answer than ignoring the filter for one press.
[ ${#CANDIDATES[@]} -gt 0 ] || CANDIDATES=("${ALL[@]}")

CURRENT=$(pactl get-default-sink 2>/dev/null)

# Not finding the current sink in the list -- it was switched off, or is gone --
# lands on the first candidate, which is the useful thing to do either way.
NEXT="${CANDIDATES[0]}"
for i in "${!CANDIDATES[@]}"; do
  if [ "${CANDIDATES[$i]}" = "$CURRENT" ]; then
    NEXT="${CANDIDATES[$(((i + 1) % ${#CANDIDATES[@]}))]}"
    break
  fi
done

pactl set-default-sink "$NEXT" || exit 1

DESC=$(pactl -f json list sinks 2>/dev/null \
       | jq -r --arg n "$NEXT" 'first(.[] | select(.name == $n) | .description) // empty' 2>/dev/null)
[ -n "$DESC" ] || DESC="$NEXT"

# The icon name is what NotificationToasts.qml matches on to pick its glyph --
# Qt never renders the SVG behind the name, so this only has to be a key both
# sides agree on. Passing the menu's own choice through is what stops the popup
# and the bar disagreeing about what this output is.
ICON_KEY=$(icon_key "$NEXT")
ICON="audio-${ICON_KEY}-symbolic"

VOL=$(get_volume)
notify-send -a "volume" -h string:x-canonical-private-synchronous:audio-volume \
  -h int:value:"$VOL" \
  -u low -i "$ICON" "$DESC: $VOL%"
