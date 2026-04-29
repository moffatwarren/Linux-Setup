#!/bin/sh
# Script to switch between speaker and headphones using wireplumber

TOGGLE=$HOME/.audio_toggle

# pactl list short sinks

if [ ! -e $TOGGLE ]; then
    touch $TOGGLE
    pactl set-default-sink alsa_output.usb-Kingston_HyperX_Amp_000000000001-00.analog-stereo
    echo "{\"text\":\"$(get_volume)%\",\"class\":\"connected\",\"alt\":\"headphones\", \"tooltip\": \"Using Headphones\"}"
    notify-send "Audio changed to HEADPHONES"
else
    rm $TOGGLE
    pactl set-default-sink alsa_output.pci-0000_00_1f.3.analog-stereo
    echo "{\"text\":\"$(get_volume)%\",\"class\":\"connected\",\"alt\":\"speaker\", \"tooltip\": \"Using Speaker\"}"
    notify-send "Audio changed to SPEAKERS"
fi
