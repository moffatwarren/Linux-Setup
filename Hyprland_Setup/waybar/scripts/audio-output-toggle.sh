#!/bin/sh
# Script to switch between speaker and headphones using wireplumber

TOGGLE=$HOME/.audio_toggle

# pactl list short sinks

if [ ! -e $TOGGLE ]; then
    touch $TOGGLE
    pactl set-default-sink alsa_output.usb-Generic_USB_Audio-00.HiFi__Speaker__sink
    echo "{\"text\":\"$(get_volume)%\",\"class\":\"connected\",\"alt\":\"headphones\", \"tooltip\": \"Using Headphones\"}"
    notify-send "Audio changed to HEADPHONES"
else
    rm $TOGGLE
    pactl set-default-sink alsa_output.usb-Actions_Razer_Nommo_V2_X_000000000000000-01.analog-stereo
    echo "{\"text\":\"$(get_volume)%\",\"class\":\"connected\",\"alt\":\"speaker\", \"tooltip\": \"Using Speaker\"}"
    notify-send "Audio changed to SPEAKERS"
fi
