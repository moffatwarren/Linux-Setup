#!/bin/bash

echo ""
echo "//////////////////////////////////"
echo "/////// INSTALLING APPS //////////"
echo "//////////////////////////////////"
echo ""

sudo pacman -S --noconfirm --needed kitty kwrite hyprland waybar hyprlock hypridle awww ttf-font-awesome swaync swappy btop fastfetch thunar tumbler slurp cliphist grim nwg-look rofi gvfs gvfs-smb samba gwenview nvim mpv imv brightnessctl blueman
paru -S --noconfirm --skipreview --needed pokemon-colorscripts-git google-chrome rustdesk-bin
sudo systemctl enable --now avahi-daemon

echo ""
echo "//////////////////////////////////"
echo "///////// MOVING FILES ///////////"
echo "//////////////////////////////////"
echo ""

\cp -rf ~/Linux-Setup/Hyprland_Setup/fastfetch ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/fish ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/hypr ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/kitty ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/rofi ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/swappy ~/.config
\cp -rf ~/Linux-Setup/Hyprland_Setup/waybar ~/.config

echo ""
echo "//////////////////////////////////"
echo "/////// ENABLING SCRIPTS /////////"
echo "//////////////////////////////////"
echo ""

chmod +x ~/Linux-Setup/Hyprland_Setup/update_dots_local.sh
chmod +x ~/.config/hypr/scripts/launch-waybar.sh
chmod +x ~/.config/hypr/scripts/wallpaper-random.sh
chmod +x ~/.config/hypr/scripts/wallpaper-selector.sh
chmod +x ~/.config/hypr/scripts/volume-notify.sh
chmod +x ~/.config/hypr/scripts/brightness-notify.sh
chmod +x ~/.config/waybar/scripts/audio-output-toggle.sh
chmod +x ~/.config/waybar/scripts/tailscale.sh

echo ""
echo "//////////////////////////////////"
echo "///////// AUDIO OUTPUT ///////////"
echo "//////////////////////////////////"
echo ""

hyprctl monitors all
pactl list short sinks

