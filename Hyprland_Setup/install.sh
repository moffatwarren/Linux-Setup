#!/bin/bash

echo "/////// INSTALLING APPS //////////"
echo ""

sudo pacman -S --noconfirm --needed kitty kwrite hyprland waybar hyprlock hypridle awww ttf-font-awesome swaync
sudo pacman -S --noconfirm --needed ttf-jetbrains-mono-nerd swappy btop fastfetch thunar tumbler slurp cliphist grim nwg-look rofi
sudo pacman -S --noconfirm --needed gvfs gvfs-smb samba gwenview nvim mpv imv brightnessctl playerctl blueman gnome-text-editor kcalc swayimg imagemagick
sudo pacman -S --noconfirm --needed thunar-archive-plugin xarchiver unzip net-tools localsend spotify-launcher
sudo pacman -S --noconfirm --needed tesseract tesseract-data-eng speedtest-cli coolercontrold lact paru
paru -S --noconfirm --skipreview --needed pokemon-colorscripts-git google-chrome rustdesk-bin teams-for-linux vscodium
sudo systemctl enable --now avahi-daemon
sudo systemctl enable --now coolercontrold
sudo systemctl enable --now lactd
sudo ln -s /usr/bin/kitty /usr/bin/xdg-terminal-exec
gsettings set org.gnome.TextEditor draw-spaces "['space', 'tab', 'trailing']"

echo ""
echo "///////// MOVING FILES ///////////"
echo ""

read -p "Do you want to get wallpapers? (y/N)" resp_wallpapers
  if [[ "$resp_wallpapers" =~ ^[Yy]$ ]]; then
    echo "Getting wallpapers..."
    \cp -rn ~/Linux-Setup/wallpapers ~/Pictures
  fi

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
chmod +x ~/.config/waybar/scripts/media.sh

echo ""
echo "///////// CHECKING OUTPUT ///////////"
echo ""

hyprctl monitors all
pactl list short sinks
