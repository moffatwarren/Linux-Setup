#!/bin/bash

# Function to send the notification
send_notification() {
    BRIGHTNESS=$(brightnessctl -m | awk -F, '{print $4}')

    notify-send -e \
                -h int:value:"$BRIGHTNESS" \
                -h string:x-canonical-private-synchronous:brightness \
                -t 1500 \
                "Brightness" "${BRIGHTNESS}%"
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
