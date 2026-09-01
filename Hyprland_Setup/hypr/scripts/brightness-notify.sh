#!/bin/bash

# Function to send the notification
send_notification() {
  BRIGHTNESS=$(brightnessctl -m | awk -F, '{print $4}' | tr -d '%')

  # The x-canonical-private-synchronous hint is what marks this as an OSD rather
  # than a message: quickshell/NotificationService.qml uses it to replace the
  # previous popup instead of stacking one, and to keep the reading out of the
  # notification list. -u low picks the compact card. The icon NAME still
  # matters -- NotificationToasts.qml matches "brightness" in it to choose the
  # glyph it draws -- but the icon file itself is no longer rendered.
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
