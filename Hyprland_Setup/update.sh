#!/bin/bash

\cp -rf ~/Linux-Setup/Hyprland_Setup/fastfetch ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/fish ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/hypr ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/kitty ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/rofi ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/swappy ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/waybar ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/nvim ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/swaync ~/.config

chmod +x ~/Linux-Setup/Hyprland_Setup/install.sh
chmod +x ~/Linux-Setup/Hyprland_Setup/update.sh
chmod +x ~/.config/hypr/scripts/wallpaper-random.sh
chmod +x ~/.config/hypr/scripts/wallpaper-selector.sh
chmod +x ~/.config/hypr/scripts/volume-notify.sh
chmod +x ~/.config/hypr/scripts/brightness-notify.sh
chmod +x ~/.config/waybar/scripts/audio-output-toggle.sh
chmod +x ~/.config/waybar/scripts/tailscale.sh
chmod +x ~/.config/waybar/scripts/weather.sh
chmod +x ~/.config/waybar/scripts/pia.sh