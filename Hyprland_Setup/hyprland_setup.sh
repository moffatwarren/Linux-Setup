#!/bin/bash

echo ""
echo "//////////////////////////////////"
echo "/////// INSTALLING APPS //////////"
echo "//////////////////////////////////"
echo ""

sudo pacman -S --noconfirm kitty kwrite hyprland waybar hyprlock hypridle hyprpaper ttf-font-awesome swaync swappy btop fastfetch thunar tumbler slurp cliphist grim nwg-look rofi gvfs gvfs-smb samba gwenview nvim
paru -S --noconfirm --skipreview pokemon-colorscripts-git
sudo systemctl enable --now avahi-daemon

echo ""
echo "//////////////////////////////////"
echo "///////// MOVING FILES ///////////"
echo "//////////////////////////////////"
echo ""

\cp -rf ~/Linx-Setup/Hyprland_Setup/fastfetch ~/.config
\cp -rf ~/Linx-Setup/Hyprland_Setup/fish ~/.config
\cp -rf ~/Linx-Setup/Hyprland_Setup/hypr ~/.config
\cp -rf ~/Linx-Setup/Hyprland_Setup/kitty ~/.config
\cp -rf ~/Linx-Setup/Hyprland_Setup/rofi ~/.config
\cp -rf ~/Linx-Setup/Hyprland_Setup/swappy ~/.config
\cp -rf ~/Linx-Setup/Hyprland_Setup/waybar ~/.config

echo ""
echo "//////////////////////////////////"
echo "/////// ENABLING SCRIPTS /////////"
echo "//////////////////////////////////"
echo ""

chmod +x ~/.config/hypr/scripts/launch-waybar.sh
chmod +x ~/.config/hypr/scripts/wallpaper-random.sh
chmod +x ~/.config/waybar/scripts/audio-output-toggle.sh
chmod +x ~/.config/waybar/scripts/tailscale.sh

echo ""
echo "//////////////////////////////////"
echo "///////// AUDIO OUTPUT ///////////"
echo "//////////////////////////////////"
echo ""

pactl list short sinks

