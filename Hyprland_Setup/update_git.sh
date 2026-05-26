#!/bin/bash

read -p "Do you want get wallpapers? (y/n) " response

case "$response" in
[yY] | [yY][eE][sS])
  echo "Getting wallpapers..."
  \cp -rn ~/Pictures/wallpapers ~/Linux-Setup
  ;;
[nN] | [nN][oO])
  echo "Not getting wallpapers..."
  ;;
*)
  echo "Invalid input. Not getting wallpapers..."
  ;;
esac

\cp -rf ~/.config/fastfetch ~/Linux-Setup/Hyprland_Setup
\cp -rf ~/.config/fish ~/Linux-Setup/Hyprland_Setup
\cp -rf ~/.config/hypr ~/Linux-Setup/Hyprland_Setup
\cp -rf ~/.config/kitty ~/Linux-Setup/Hyprland_Setup
\cp -rf ~/.config/rofi ~/Linux-Setup/Hyprland_Setup
\cp -rf ~/.config/swappy ~/Linux-Setup/Hyprland_Setup
\cp -rf ~/.config/waybar ~/Linux-Setup/Hyprland_Setup
\cp -rf ~/.config/nvim ~/Linux-Setup/Hyprland_Setup