#!/bin/bash

echo "/////// INSTALLING APPS //////////"
echo ""

sudo pacman -S --noconfirm --needed kitty kwrite hyprland waybar hyprlock hypridle awww ttf-font-awesome swaync ttf-jetbrains-mono-nerd swappy btop fastfetch thunar tumbler slurp cliphist grim nwg-look rofi gvfs gvfs-smb samba gwenview nvim mpv imv brightnessctl blueman
paru -S --noconfirm --skipreview --needed pokemon-colorscripts-git google-chrome rustdesk-bin
sudo systemctl enable --now avahi-daemon

echo ""
echo "///////// MOVING FILES ///////////"
echo ""

read -p "Do you want get wallpapers? (y/n) " response

case "$response" in
[yY] | [yY][eE][sS])
  echo "Getting wallpapers..."
  \cp -rn ~/Linux-Setup/Hyprland_Setup/wallpapers ~/Pictures
  ;;
[nN] | [nN][oO])
  echo "Not getting wallpapers..."
  ;;
*)
  echo "Invalid input. Not getting wallpapers..."
  ;;
esac

\cp -rf ~/Linux-Setup/Hyprland_Setup/fastfetch ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/fish ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/hypr ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/kitty ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/rofi ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/swappy ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/waybar ~/.config

chmod +x ~/Linux-Setup/Hyprland_Setup/update_dots_local.sh
chmod +x ~/.config/hypr/scripts/launch-waybar.sh
chmod +x ~/.config/hypr/scripts/wallpaper-random.sh
chmod +x ~/.config/hypr/scripts/wallpaper-selector.sh
chmod +x ~/.config/hypr/scripts/volume-notify.sh
chmod +x ~/.config/hypr/scripts/brightness-notify.sh
chmod +x ~/.config/waybar/scripts/audio-output-toggle.sh
chmod +x ~/.config/waybar/scripts/tailscale.sh

read -p "Do you want to set monitor to 2560x1440@240? (y/n) " response

case "$response" in
[yY] | [yY][eE][sS])
  sed -i '/monitor=/c\monitor=,2560x1440@240,auto,1' ~/.config/hypr/hyprland.conf
  echo "Monitor set to 2560x1440@240"
  ;;
[nN] | [nN][oO])
  echo "Monitor set to preferred"
  ;;
*)
  echo "Invalid input. Monitor set to preferred"
  ;;
esac

echo ""
echo "///////// CHECKING OUTPUT ///////////"
echo ""

hyprctl monitors all
pactl list short sinks
