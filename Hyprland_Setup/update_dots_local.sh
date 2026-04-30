#!/bin/bash

read -p "Do you want update the wallpapers? (y/n) " response

case "$response" in
[yY] | [yY][eE][sS])
  echo "Updating wallpapers..."
  \cp -rn ~/Pictures/wallpapers ~/Linux-Setup/Hyprland_Setup/
  ;;
[nN] | [nN][oO])
  echo "Not updating wallpapers..."
  ;;
*)
  echo "Invalid input. Not updating wallpapers..."
  ;;
esac

\cp -rf ~/.config/fastfetch ~/Linux-Setup/Hyprland_Setup
\cp -rf ~/.config/hypr ~/Linux-Setup/Hyprland_Setup
\cp -rf ~/.config/kitty ~/Linux-Setup/Hyprland_Setup
\cp -rf ~/.config/rofi ~/Linux-Setup/Hyprland_Setup
\cp -rf ~/.config/swappy ~/Linux-Setup/Hyprland_Setup
\cp -rf ~/.config/waybar ~/Linux-Setup/Hyprland_Setup
\cp ~/.config/fish/config.fish ~/Linux-Setup/Hyprland_Setup/fish
