#!/bin/bash

# Check if playerctl is installed
if ! command -v playerctl &> /dev/null; then
    exit 0
fi

# Get the list of all running players
players=$(playerctl -l 2>/dev/null)
if [ -z "$players" ]; then
    exit 0
fi

# Find the active player (prefer "Playing", fallback to "Paused")
active_player=""
for p in $players; do
    status=$(playerctl -p "$p" status 2>/dev/null)
    if [ "$status" = "Playing" ]; then
        active_player="$p"
        break
    fi
done

if [ -z "$active_player" ]; then
    for p in $players; do
        status=$(playerctl -p "$p" status 2>/dev/null)
        if [ "$status" = "Paused" ]; then
            active_player="$p"
            break
        fi
    done
fi

# If no active player found, exit
if [ -z "$active_player" ]; then
    exit 0
fi

status=$(playerctl -p "$active_player" status 2>/dev/null)

case "$1" in
    "art")
        art_url=$(playerctl -p "$active_player" metadata mpris:artUrl 2>/dev/null)
        if [ -z "$art_url" ]; then
            exit 0
        fi

        if [[ "$art_url" == file://* ]]; then
            echo "${art_url#file://}"
            exit 0
        elif [[ "$art_url" == http://* || "$art_url" == https://* ]]; then
            cache_dir="/tmp/waybar-media"
            mkdir -p "$cache_dir"
            url_hash=$(echo -n "$art_url" | md5sum | cut -d' ' -f1)
            cache_file="$cache_dir/$url_hash.png"
            if [ ! -f "$cache_file" ]; then
                curl -s --connect-timeout 1 --max-time 2 "$art_url" -o "$cache_file"
            fi
            echo "$cache_file"
            exit 0
        fi
        ;;
    "prev")
        echo "󰒮"
        ;;
    "next")
        echo "󰒭"
        ;;
    "play-pause")
        if [ "$status" = "Playing" ]; then
            echo "󰏤"  # Pause icon
        else
            echo "󰐊"  # Play icon
        fi
        ;;
    "title")
        artist=$(playerctl -p "$active_player" metadata artist 2>/dev/null)
        title=$(playerctl -p "$active_player" metadata title 2>/dev/null)
        if [ -n "$artist" ] && [ -n "$title" ]; then
            echo "$artist - $title"
        elif [ -n "$title" ]; then
            echo "$title"
        else
            echo "Unknown Media"
        fi
        ;;
    "prev-action")
        playerctl -p "$active_player" previous
        ;;
    "next-action")
        playerctl -p "$active_player" next
        ;;
    "play-pause-toggle")
        playerctl -p "$active_player" play-pause
        ;;
    *)
        exit 1
        ;;
esac
