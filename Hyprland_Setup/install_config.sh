#!/bin/bash

echo ""
echo "///////// MOVING FILES ///////////"
echo ""

\cp -rf ~/Linux-Setup/Hyprland_Setup/fastfetch ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/fish ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/hypr ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/kitty ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/rofi ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/swappy ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/waybar ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/nvim ~/.config

chmod +x ~/Linux-Setup/Hyprland_Setup/install_all.sh
chmod +x ~/Linux-Setup/Hyprland_Setup/install_config.sh
chmod +x ~/Linux-Setup/Hyprland_Setup/update_wallpapers.sh
chmod +x ~/.config/hypr/scripts/launch-waybar.sh
chmod +x ~/.config/hypr/scripts/wallpaper-random.sh
chmod +x ~/.config/hypr/scripts/wallpaper-selector.sh
chmod +x ~/.config/hypr/scripts/volume-notify.sh
chmod +x ~/.config/hypr/scripts/brightness-notify.sh
chmod +x ~/.config/waybar/scripts/audio-output-toggle.sh
chmod +x ~/.config/waybar/scripts/tailscale.sh
chmod +x ~/.config/waybar/scripts/weather.sh
