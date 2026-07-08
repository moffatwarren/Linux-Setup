#!/bin/bash

sudo pacman -S --noconfirm --needed kitty kwrite hyprland waybar hyprlock hypridle awww ttf-font-awesome swaync
sudo pacman -S --noconfirm --needed ttf-jetbrains-mono-nerd swappy btop fastfetch thunar tumbler slurp cliphist grim nwg-look rofi
sudo pacman -S --noconfirm --needed gvfs gvfs-smb samba gwenview nvim mpv imv brightnessctl playerctl blueman gnome-text-editor kcalc swayimg imagemagick
sudo pacman -S --noconfirm --needed thunar-archive-plugin xarchiver unzip net-tools localsend spotify-launcher
sudo pacman -S --noconfirm --needed tesseract tesseract-data-eng speedtest-cli paru
paru -S --noconfirm --skipreview --needed pokemon-colorscripts-git rustdesk-bin teams-for-linux vscodium-bin

first_install=true

read -p "Is this the first install (y/N): " resp_install

if [[ ! "$resp_install" =~ ^[Yy]$ ]]; then
    first_install=false
else
    sudo systemctl enable --now avahi-daemon
    sudo ln -s /usr/bin/kitty /usr/bin/xdg-terminal-exec
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
                live_headphone=$(grep -E '^\s*HEADPHONE_SINK\s*=' "$HOME/.config/waybar/scripts/audio-output-toggle.sh")
                live_speaker=$(grep -E '^\s*SPEAKER_SINK\s*=' "$HOME/.config/waybar/scripts/audio-output-toggle.sh")
            fi
            
            # Extract live format-icons block if the config file exists
            if [ -f "$HOME/.config/waybar/config" ]; then
                live_icons=$(python3 -c '
    import re, sys
    try:
        with open(sys.argv[1], "r", encoding="utf-8") as f:
            content = f.read()
        pulse_match = re.search(r"\"pulseaudio\"\s*:\s*\{", content)
        if pulse_match:
            start_idx = pulse_match.end() - 1
            brace_count = 0
            end_idx = -1
            for i in range(start_idx, len(content)):
                if content[i] == "{":
                    brace_count += 1
                elif content[i] == "}":
                    brace_count -= 1
                    if brace_count == 0:
                        end_idx = i + 1
                        break
            if end_idx != -1:
                pulse_block = content[start_idx:end_idx]
                icons_match = re.search(r"\"format-icons\"\s*:\s*([{\[])", pulse_block)
                if icons_match:
                    icons_start_char = icons_match.group(1)
                    icons_start_idx = start_idx + icons_match.start()
                    count = 0
                    icons_end_idx = -1
                    open_char = icons_start_char
                    close_char = "}" if open_char == "{" else "]"
                    for i in range(start_idx + icons_match.end() - 1, len(content)):
                        if content[i] == open_char:
                            count += 1
                        elif content[i] == close_char:
                            count -= 1
                            if count == 0:
                                icons_end_idx = i + 1
                                break
                    if icons_end_idx != -1:
                        sys.stdout.write(content[icons_start_idx:icons_end_idx])
    except Exception as e:
        sys.stderr.write(str(e))
    ' "$HOME/.config/waybar/config")
            fi
        fi
    fi
    
    overwrite_monitor=true
    if [ -f "$HOME/.config/hypr/modules/config.lua" ]; then
        read -p "Overwrite mainMonitor value? (y/N): " resp_monitor
        if [[ ! "$resp_monitor" =~ ^[Yy]$ ]]; then
            overwrite_monitor=false
            live_main_monitor=$(grep -E '^\s*config\.mainMonitor\s*=' "$HOME/.config/hypr/modules/config.lua")
        fi
    fi
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

if [ "$first_install" = false ]; then
    # Restore live audio sink values if requested
    if [ "$overwrite_audio" = false ]; then
        python3 -c '
    import sys, re
    file_path = sys.argv[1]
    hp_line = sys.argv[2]
    sp_line = sys.argv[3]
    
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    
        new_lines = []
        for line in lines:
            if re.match(r"^\s*HEADPHONE_SINK\s*=", line) and hp_line:
                new_lines.append(hp_line + "\n")
            elif re.match(r"^\s*SPEAKER_SINK\s*=", line) and sp_line:
                new_lines.append(sp_line + "\n")
            else:
                new_lines.append(line)
    
        with open(file_path, "w", encoding="utf-8") as f:
            f.writelines(new_lines)
    except Exception as e:
        sys.stderr.write(str(e))
    ' "$HOME/.config/waybar/scripts/audio-output-toggle.sh" "$live_headphone" "$live_speaker"
    fi
    
    # Restore live waybar config format-icons if requested
    if [ "$overwrite_config" = false ] && [ -n "$live_icons" ]; then
        python3 -c '
    import sys, re
    file_path = sys.argv[1]
    live_icons_str = sys.argv[2]
    
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
    
        pulse_match = re.search(r"\"pulseaudio\"\s*:\s*\{", content)
        if pulse_match:
            start_idx = pulse_match.end() - 1
            brace_count = 0
            end_idx = -1
            for i in range(start_idx, len(content)):
                if content[i] == "{":
                    brace_count += 1
                elif content[i] == "}":
                    brace_count -= 1
                    if brace_count == 0:
                        end_idx = i + 1
                        break
            if end_idx != -1:
                pulse_block = content[start_idx:end_idx]
                icons_match = re.search(r"\"format-icons\"\s*:\s*([{\[])", pulse_block)
                if icons_match:
                    icons_start_char = icons_match.group(1)
                    icons_start_idx = start_idx + icons_match.start()
                    count = 0
                    icons_end_idx = -1
                    open_char = icons_start_char
                    close_char = "}" if open_char == "{" else "]"
                    for i in range(start_idx + icons_match.end() - 1, len(content)):
                        if content[i] == open_char:
                            count += 1
                        elif content[i] == close_char:
                            count -= 1
                            if count == 0:
                                icons_end_idx = i + 1
                                break
                    if icons_end_idx != -1:
                        new_content = content[:icons_start_idx] + live_icons_str + content[icons_end_idx:]
                        with open(file_path, "w", encoding="utf-8") as f:
                            f.write(new_content)
    except Exception as e:
        sys.stderr.write(str(e))
    ' "$HOME/.config/waybar/config" "$live_icons"
    fi
    
    # Restore live config.mainMonitor value if requested
    if [ "$overwrite_monitor" = false ] && [ -n "$live_main_monitor" ]; then
        python3 -c '
    import sys, re
    file_path = sys.argv[1]
    monitor_line = sys.argv[2]
    
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
    
        new_lines = []
        for line in lines:
            if re.match(r"^\s*config\.mainMonitor\s*=", line):
                new_lines.append(monitor_line + "\n")
            else:
                new_lines.append(line)
    
        with open(file_path, "w", encoding="utf-8") as f:
            f.writelines(new_lines)
    except Exception as e:
        sys.stderr.write(str(e))
    ' "$HOME/.config/hypr/modules/config.lua" "$live_main_monitor"
    fi
fi

chmod +x ~/Linux-Setup/Hyprland_Setup/install.sh
chmod +x ~/.config/hypr/scripts/wallpaper-random.sh
chmod +x ~/.config/hypr/scripts/wallpaper-selector.sh
chmod +x ~/.config/hypr/scripts/volume-notify.sh
chmod +x ~/.config/hypr/scripts/brightness-notify.sh
chmod +x ~/.config/waybar/scripts/audio-output-toggle.sh
chmod +x ~/.config/waybar/scripts/tailscale.sh
chmod +x ~/.config/waybar/scripts/weather.sh
chmod +x ~/.config/waybar/scripts/pia.sh
chmod +x ~/.config/waybar/scripts/media.sh

read -p "Do you want to get wallpapers? (y/N)" resp_wallpapers
if [[ "$resp_wallpapers" =~ ^[Yy]$ ]]; then
echo "Getting wallpapers..."
\cp -rn ~/Linux-Setup/wallpapers ~/Pictures
fi
