#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

sudo pacman -S --noconfirm --needed \
    kitty hyprland waybar hyprlock hypridle awww ttf-font-awesome swaync \
    ttf-jetbrains-mono-nerd swappy btop fastfetch thunar tumbler slurp cliphist grim nwg-look rofi \
    gvfs gvfs-smb samba nvim mpv imv brightnessctl playerctl blueman gnome-text-editor swayimg imagemagick \
    thunar-archive-plugin xarchiver unzip net-tools localsend spotify-launcher \
    tesseract tesseract-data-eng speedtest-cli brave-origin-bin paru
paru -S --noconfirm --skipreview --needed pokemon-colorscripts-git rustdesk-bin teams-for-linux vscodium-bin weathr-bin

first_install=true

read -p "Is this the first install (y/N): " resp_install

if [[ ! "$resp_install" =~ ^[Yy]$ ]]; then
    first_install=false
else
    sudo systemctl enable --now avahi-daemon
    sudo ln -sf /usr/bin/kitty /usr/bin/xdg-terminal-exec
    gsettings set org.gnome.TextEditor draw-spaces "['space', 'tab', 'trailing']"
fi

if [ "$first_install" = false ]; then
    overwrite_audio=true
    overwrite_config=true

    if [ -f "$HOME/.config/waybar/scripts/audio-output-toggle.sh" ] || [ -f "$HOME/.config/waybar/config" ]; then
        read -p "Overwrite audio sink values? (y/N): " resp_audio

        if [[ ! "$resp_audio" =~ ^[Yy]$ ]]; then
            overwrite_audio=false
            overwrite_config=false

            # Extract live audio-output-toggle sink values if the file exists
            if [ -f "$HOME/.config/waybar/scripts/audio-output-toggle.sh" ]; then
                # BUILT_IN_SINK is also reassigned indented inside the toggle logic,
                # so anchor to column 0 to only capture the top-level assignment
                live_built_in=$(grep -E '^BUILT_IN_SINK\s*=' "$HOME/.config/waybar/scripts/audio-output-toggle.sh" || true)
                live_headphone=$(grep -E '^\s*HEADPHONE_SINK\s*=' "$HOME/.config/waybar/scripts/audio-output-toggle.sh" || true)
                live_speaker=$(grep -E '^\s*SPEAKER_SINK\s*=' "$HOME/.config/waybar/scripts/audio-output-toggle.sh" || true)
                live_bluetooth=$(grep -E '^\s*BLUETOOTH_SINK\s*=' "$HOME/.config/waybar/scripts/audio-output-toggle.sh" || true)
            fi

            # Extract live format-icons block if the config file exists
            if [ -f "$HOME/.config/waybar/config" ]; then
                live_icons=$(python3 "$SCRIPT_DIR/install_lib/waybar_format_icons.py" get "$HOME/.config/waybar/config")
            fi
        fi
    fi

    overwrite_monitor=true
    if [ -f "$HOME/.config/hypr/modules/config.lua" ]; then
        read -p "Overwrite mainMonitor value? (y/N): " resp_monitor
        if [[ ! "$resp_monitor" =~ ^[Yy]$ ]]; then
            overwrite_monitor=false
            live_main_monitor=$(grep -E '^\s*config\.mainMonitor\s*=' "$HOME/.config/hypr/modules/config.lua" || true)
        fi
    fi
fi

\cp -rf "$SCRIPT_DIR/fastfetch" "$HOME/.config"
\cp -rf "$SCRIPT_DIR/fish" "$HOME/.config"
\cp -rf "$SCRIPT_DIR/hypr" "$HOME/.config"
\cp -rf "$SCRIPT_DIR/kitty" "$HOME/.config"
\cp -rf "$SCRIPT_DIR/rofi" "$HOME/.config"
\cp -rf "$SCRIPT_DIR/swappy" "$HOME/.config"
\cp -rf "$SCRIPT_DIR/waybar" "$HOME/.config"
\cp -rf "$SCRIPT_DIR/nvim" "$HOME/.config"
\cp -rf "$SCRIPT_DIR/swaync" "$HOME/.config"
\cp -rf "$SCRIPT_DIR/weathr" "$HOME/.config"
sudo \cp -rf "$SCRIPT_DIR/voidsddm" /usr/share/sddm/themes
sudo \cp -rf "$SCRIPT_DIR/sddm.conf.d" /etc

if [ "$first_install" = false ]; then
    # Restore live audio sink values if requested
    if [ "$overwrite_audio" = false ]; then
        python3 "$SCRIPT_DIR/install_lib/replace_line.py" "$HOME/.config/waybar/scripts/audio-output-toggle.sh" \
            '^BUILT_IN_SINK\s*=' "${live_built_in:-}" \
            '^\s*HEADPHONE_SINK\s*=' "${live_headphone:-}" \
            '^\s*SPEAKER_SINK\s*=' "${live_speaker:-}" \
            '^\s*BLUETOOTH_SINK\s*=' "${live_bluetooth:-}"
    fi

    # Restore live waybar config format-icons if requested
    if [ "$overwrite_config" = false ] && [ -n "${live_icons:-}" ]; then
        python3 "$SCRIPT_DIR/install_lib/waybar_format_icons.py" set "$HOME/.config/waybar/config" "$live_icons"
    fi

    # Restore live config.mainMonitor value if requested
    if [ "$overwrite_monitor" = false ] && [ -n "${live_main_monitor:-}" ]; then
        python3 "$SCRIPT_DIR/install_lib/replace_line.py" "$HOME/.config/hypr/modules/config.lua" \
            '^\s*config\.mainMonitor\s*=' "$live_main_monitor"
    fi
fi

chmod +x "$SCRIPT_DIR/install.sh"
find "$HOME/.config/hypr/scripts" "$HOME/.config/waybar/scripts" -type f -name '*.sh' -exec chmod +x {} +

read -p "Do you want to get wallpapers? (y/N): " resp_wallpapers
if [[ "$resp_wallpapers" =~ ^[Yy]$ ]]; then
    echo "Getting wallpapers..."
    \cp -rn "$REPO_ROOT/wallpapers" "$HOME/Pictures"
fi
