#!/bin/bash

echo "/////// INSTALLING APPS //////////"
echo ""

sudo pacman -S --noconfirm --needed kitty kwrite hyprland waybar hyprlock hypridle awww ttf-font-awesome swaync
sudo pacman -S --noconfirm --needed ttf-jetbrains-mono-nerd swappy btop fastfetch thunar tumbler slurp cliphist grim nwg-look rofi
sudo pacman -S --noconfirm --needed gvfs gvfs-smb samba gwenview nvim mpv imv brightnessctl blueman gnome-text-editor kcalc swayimg
sudo pacman -S --noconfirm --needed thunar-archive-plugin xarchiver unzip
paru -S --noconfirm --skipreview --needed pokemon-colorscripts-git google-chrome rustdesk-bin teams-for-linux vscodium
sudo systemctl enable --now avahi-daemon
sudo ln -s /usr/bin/kitty /usr/bin/xdg-terminal-exec
gsettings set org.gnome.TextEditor draw-spaces "['space', 'tab', 'trailing']"

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
\cp -rf ~/Linux-Setup/Hyprland_Setup/nvim ~/.config

chmod +x ~/Linux-Setup/Hyprland_Setup/update_dots_local.sh
chmod +x ~/.config/hypr/scripts/launch-waybar.sh
chmod +x ~/.config/hypr/scripts/wallpaper-random.sh
chmod +x ~/.config/hypr/scripts/wallpaper-selector.sh
chmod +x ~/.config/hypr/scripts/volume-notify.sh
chmod +x ~/.config/hypr/scripts/brightness-notify.sh
chmod +x ~/.config/waybar/scripts/audio-output-toggle.sh
chmod +x ~/.config/waybar/scripts/tailscale.sh

echo ""
echo "///////// CHECKING OUTPUT ///////////"
echo ""

hyprctl monitors all
pactl list short sinks
