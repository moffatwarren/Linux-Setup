#!/bin/sh

# pactl list short sinks
BUILT_IN_SINK="alsa_output.pci-0000_07_00.6.HiFi__Speaker__sink"
HEADPHONE_SINK="alsa_output.pci-0000_07_00.6.HiFi__Headphones__sink"
SPEAKER_SINK="alsa_output.usb-KTMicro_KT_USB_Audio_2021-06-07-0000-0000-0000--00.analog-stereo"
BLUETOOTH_SINK="bluez_output.B4_23_A2_0B_AA_DF.1"
CURRENT_SINK=$(pactl get-default-sink)

get_volume() {
  wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}'
}

if pactl list short sinks | grep -F -q "$SPEAKER_SINK"; then
  BUILT_IN_SINK="$SPEAKER_SINK"
fi

if [ "$CURRENT_SINK" = "$BUILT_IN_SINK" ]; then
  if pactl list short sinks | grep -F -q "$HEADPHONE_SINK"; then
    pactl set-default-sink "$HEADPHONE_SINK"
    notify-send -h string:x-canonical-private-synchronous:audio-volume \
      -h int:value:"$(get_volume)" \
      -u low -i audio-volume-high "Headphone Volume: $(get_volume)%"
  elif pactl list short sinks | grep -F -q "$BLUETOOTH_SINK"; then
    pactl set-default-sink "$BLUETOOTH_SINK"
    notify-send -h string:x-canonical-private-synchronous:audio-volume \
      -h int:value:"$(get_volume)" \
      -u low -i audio-volume-high "Bluetooth Earbud Volume: $(get_volume)%"
  else
    pactl set-default-sink "$BUILT_IN_SINK"
    notify-send -h string:x-canonical-private-synchronous:audio-volume \
      -h int:value:"$(get_volume)" \
      -u low -i audio-volume-high "Speaker Volume: $(get_volume)%"
  fi
elif [ "$CURRENT_SINK" = "$HEADPHONE_SINK" ]; then
  if pactl list short sinks | grep -F -q "$BLUETOOTH_SINK"; then
    pactl set-default-sink "$BLUETOOTH_SINK"
    notify-send -h string:x-canonical-private-synchronous:audio-volume \
      -h int:value:"$(get_volume)" \
      -u low -i audio-volume-high "Bluetooth Earbud Volume: $(get_volume)%"
  else
    pactl set-default-sink "$BUILT_IN_SINK"
    notify-send -h string:x-canonical-private-synchronous:audio-volume \
      -h int:value:"$(get_volume)" \
      -u low -i audio-volume-high "Speaker Volume: $(get_volume)%"
  fi
else
  pactl set-default-sink "$BUILT_IN_SINK"
  notify-send -h string:x-canonical-private-synchronous:audio-volume \
    -h int:value:"$(get_volume)" \
    -u low -i audio-volume-high "Speaker Volume: $(get_volume)%"
fi
