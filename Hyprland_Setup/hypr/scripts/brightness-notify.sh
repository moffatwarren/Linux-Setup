#!/bin/bash

# Function to send the notification
send_notification() {
  BRIGHTNESS=$(brightnessctl -m | awk -F, '{print $4}' | tr -d '%')

  # -u low so it gets the same compact OSD styling as the volume popup; see
  # swaync/style.css. The symbolic icon is flat line art the stylesheet recolours.
  notify-send -a "brightness" -e -u low \
    -h int:value:"$BRIGHTNESS" \
    -h string:x-canonical-private-synchronous:brightness \
    -i display-brightness-symbolic \
    -t 1500 \
    "Brightness: ${BRIGHTNESS}%"
}

# Handle the arguments passed from Hyprland
case $1 in
up)
  brightnessctl set 5%+
  send_notification
  ;;
down)
  brightnessctl set 5%-
  send_notification
  ;;
*)
  echo "Brightness: $0 {up|down}"
  exit 1
  ;;
esac
