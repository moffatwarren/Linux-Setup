#!/bin/bash

# Function to get the current volume percentage
get_volume() {
    wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}'
}

# Function to check if the volume is muted
get_mute() {
    wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED && echo "yes" || echo "no"
}

# Function to send the notification
send_notification() {
    volume=$(get_volume)
    mute=$(get_mute)

    # The 'x-canonical-private-synchronous' hint tells SwayNC to replace the existing notification
    if [ "$mute" == "yes" ]; then
        notify-send -h string:x-canonical-private-synchronous:audio-volume \
                    -u low -i audio-volume-muted "Volume Muted"
    else
        notify-send -h string:x-canonical-private-synchronous:audio-volume \
                    -h int:value:"$volume" \
                    -u low -i audio-volume-high "Volume: ${volume}%"
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
