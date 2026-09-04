#!/bin/bash
# Deploy this repo's configs to the live system (and pull live changes back).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Config directories: Hyprland_Setup/<name> -> ~/.config/<name>
CONFIGS=(btop fastfetch fish gtk-3.0 gtk-4.0 hypr kitty nvim quickshell swappy weathr)

# Retired config paths to purge from ~/.config
ORPHANS=(
    rofi
    hypr/scripts/clipboard-menu.sh
    hypr/scripts/wallpaper-selector.sh
    hypr/modules/utils/wallpaper_utils.lua
    gtk-3.0/noctalia.css
    gtk-4.0/noctalia.css
    swaync
    quickshell/TrayPill.qml
    quickshell/TrayMenu.qml
    quickshell/TrayMenuItems.qml
    hypr/scripts/monitor-toggle.sh
    hypr/scripts/weather.sh
)

PACMAN_PKGS=(
    kitty hyprland quickshell hyprlock hypridle awww ttf-font-awesome
    ttf-jetbrains-mono-nerd swappy btop fastfetch thunar tumbler slurp cliphist grim nwg-look
    wf-recorder gvfs gvfs-smb samba nvim mpv imv brightnessctl playerctl blueman gnome-text-editor
    swayimg imagemagick thunar-archive-plugin xarchiver unzip net-tools localsend spotify-launcher
    speedtest-cli brave-origin-bin paru tesseract tesseract-data-eng adw-gtk-theme cantarell-fonts
    papirus-icon-theme jq libpulse wireplumber pavucontrol power-profiles-daemon networkmanager
    qt6-imageformats libnotify wl-clipboard curl python pacman-contrib fakeroot sddm avahi
)

PARU_PKGS=(
    pokemon-colorscripts-git rustdesk-bin teams-for-linux vscodium-bin
    papirus-folders-catppuccin-git
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

usage() {
    cat <<EOF
Usage: install.sh [OPTION]

  (no option)   Install packages and deploy this repo's configs to the live
                system. Handles both first-time install and routine updates;
                the only question it asks is whether to copy in the wallpapers.
  --pull        Copy the LIVE configs back into this repo so changes made on
                the machine can be reviewed and committed. Does not commit.
  --help        Show this message.
EOF
}

## Migrate legacy audio sink declarations into quickshell-audio.json cache
migrate_audio_icons() {
    local legacy="" state="$HOME/.cache/quickshell-audio.json" tmp
    local candidate headphone="" bluetooth=""

    for candidate in "$HOME/.config/hypr/scripts/audio-output-toggle.sh" \
                     "$HOME/.config/waybar/scripts/audio-output-toggle.sh"; do
        if [ -f "$candidate" ] && grep -qE '^[[:space:]]*HEADPHONE_SINK[[:space:]]*=' "$candidate"; then
            legacy="$candidate"
            break
        fi
    done
    [ -n "$legacy" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0

    headphone="$(sed -nE 's/^[[:space:]]*HEADPHONE_SINK[[:space:]]*=[[:space:]]*"?([^"]*)"?.*/\1/p' "$legacy" | head -1)"
    bluetooth="$(sed -nE 's/^[[:space:]]*BLUETOOTH_SINK[[:space:]]*=[[:space:]]*"?([^"]*)"?.*/\1/p' "$legacy" | head -1)"
    [ -n "$headphone" ] || [ -n "$bluetooth" ] || return 0

    info "Migrating audio icons to quickshell cache"
    mkdir -p "$(dirname "$state")"
    [ -f "$state" ] || printf '{ "outputs": [] }\n' > "$state"

    tmp="$(mktemp)"
    if jq --arg hp "$headphone" --arg bt "$bluetooth" '
          def seed($name; $icon):
            if $name == "" then .
            elif [.outputs[]?.name] | index($name) then
              .outputs |= map(if .name == $name and (.icon // "") == "" then .icon = $icon else . end)
            else .outputs += [{ name: $name, description: $name, enabled: true, icon: $icon }]
            end;
          (.outputs //= []) | seed($hp; "headphones") | seed($bt; "bluetooth")
       ' "$state" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$state"
        [ -n "$headphone" ] && echo "    headphones -> $headphone"
        [ -n "$bluetooth" ] && echo "    bluetooth  -> $bluetooth"
    else
        rm -f "$tmp"
    fi
}

LOCK_WALLPAPER=""

save_lock_wallpaper() {
    local conf="$HOME/.config/hypr/hyprlock.conf"
    [ -f "$conf" ] || return 0
    LOCK_WALLPAPER="$(sed -n 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*//p' "$conf" | head -1)"
}

restore_lock_wallpaper() {
    local conf="$HOME/.config/hypr/hyprlock.conf"
    [ -n "$LOCK_WALLPAPER" ] || return 0
    [ -f "$conf" ] || return 0
    [ -f "$LOCK_WALLPAPER" ] || return 0
    sed -i "s|^\([[:space:]]*\)path = .*|\1path = ${LOCK_WALLPAPER//&/\\&}|" "$conf"
    echo "    kept live hyprlock background: $LOCK_WALLPAPER"
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
install_packages() {
    info "Installing packages"
    sudo pacman -S --noconfirm --needed "${PACMAN_PKGS[@]}"
    paru -S --noconfirm --skipreview --needed "${PARU_PKGS[@]}"

    check_nerd_font
}

# Verify required Nerd Font v3 glyphs exist
check_nerd_font() {
    command -v fc-list >/dev/null 2>&1 || return 0

    local cp missing=()
    for cp in f0200 f057e f033e f03d7; do
        if ! fc-list ":charset=$cp:family=JetBrainsMono Nerd Font" 2>/dev/null | grep -q .; then
            missing+=("U+${cp^^}")
        fi
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        echo "    nerd font: v3 glyphs present"
        return 0
    fi

    echo "    WARNING: JetBrainsMono Nerd Font is missing ${missing[*]} (v3 codepoints)."
    echo "             Icon modules may render incorrectly."
}

# Warn if systemd-logind lid settings deviate from defaults
check_lid_handling() {
    command -v busctl >/dev/null 2>&1 || return 0
    compgen -G '/sys/class/drm/card*-eDP-*' >/dev/null 2>&1 ||
        compgen -G '/sys/class/drm/card*-LVDS-*' >/dev/null 2>&1 ||
        compgen -G '/sys/class/drm/card*-DSI-*' >/dev/null 2>&1 || return 0

    local prop want got warned=0
    for prop in "HandleLidSwitch=suspend" "HandleLidSwitchDocked=ignore" \
                "HandleLidSwitchExternalPower="; do
        want="${prop#*=}"
        got="$(busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1 \
               org.freedesktop.login1.Manager "${prop%%=*}" 2>/dev/null \
               | sed -n 's/^s "\(.*\)"$/\1/p')"
        if [ "$got" != "$want" ]; then
            if [ "$warned" -eq 0 ]; then
                echo "    WARNING: non-default lid handling detected:"
                warned=1
            fi
            echo "               ${prop%%=*} is '${got}', expected '${want}'"
        fi
    done

    if [ "$warned" -eq 0 ]; then
        echo "    lid handling: logind defaults"
    fi
}

deploy_configs() {
    info "Deploying configs to ~/.config"
    local c
    for c in "${CONFIGS[@]}"; do
        if [ ! -d "$SCRIPT_DIR/$c" ]; then
            echo "    skip $c (no $SCRIPT_DIR/$c)"
            continue
        fi
        \cp -rf "$SCRIPT_DIR/$c" "$HOME/.config"
        echo "    $c"
    done
    sudo mkdir -p /usr/share/sddm/themes
    sudo \cp -rf "$SCRIPT_DIR/voidsddm" /usr/share/sddm/themes
    sudo \cp -rf "$SCRIPT_DIR/sddm.conf.d" /etc
    echo "    voidsddm + sddm.conf.d (system)"
}

# Delete what an older release of this repo deployed and this one has dropped
remove_orphans() {
    info "Removing retired configs"
    local p target found=0
    for p in "${ORPHANS[@]}"; do
        [ -n "$p" ] || continue
        if [ -e "$SCRIPT_DIR/$p" ]; then
            continue
        fi
        target="$HOME/.config/$p"
        if [ -e "$target" ]; then
            rm -rf "$target"
            echo "    removed $p"
            found=1
        fi
    done
    if [ "$found" -eq 0 ]; then
        echo "    nothing to remove"
    fi
}

# Retire swaync daemon so quickshell owns org.freedesktop.Notifications
retire_swaync() {
    if ! command -v swaync >/dev/null 2>&1; then
        return 0
    fi

    info "Retiring swaync"
    pkill -x swaync >/dev/null 2>&1 || true

    if systemctl --user mask swaync.service >/dev/null 2>&1; then
        echo "    masked swaync.service"
    fi
}

fix_permissions() {
    chmod +x "$SCRIPT_DIR/install.sh"
    local c d
    for c in "${CONFIGS[@]}"; do
        d="$HOME/.config/$c/scripts"
        if [ -d "$d" ]; then
            find "$d" -type f -name '*.sh' -exec chmod +x {} +
        fi
    done
}

# Apply GTK theme, Papirus icon folder colors, and gsettings
apply_gtk_theme() {
    info "Applying GTK theme"

    if ! command -v papirus-folders >/dev/null 2>&1; then
        echo "    skip papirus-folders (not installed)"
    elif papirus-folders -C cat-mocha-blue --theme Papirus-Dark >/dev/null 2>&1; then
        echo "    Papirus-Dark folders -> cat-mocha-blue"
    else
        echo "    WARNING: papirus-folders failed -- folders keep the stock Papirus blue."
        echo "             Everything else is themed. Retry by hand with:"
        echo "               papirus-folders -C cat-mocha-blue --theme Papirus-Dark"
    fi

    gsettings set org.gnome.desktop.interface gtk-theme    "adw-gtk3-dark"
    gsettings set org.gnome.desktop.interface icon-theme   "Papirus-Dark"
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
    gsettings set org.gnome.desktop.interface font-name    "Cantarell 11"
    echo "    gsettings: adw-gtk3-dark / Papirus-Dark / prefer-dark"

    if command -v thunar >/dev/null 2>&1; then
        thunar -q >/dev/null 2>&1 || true
    fi
}

# System settings (mDNS daemon, terminal handler, text editor whitespace)
apply_system_tweaks() {
    info "Applying system settings"

    sudo systemctl enable --now avahi-daemon
    echo "    avahi-daemon enabled"

    sudo ln -sf /usr/bin/kitty /usr/bin/xdg-terminal-exec
    echo "    xdg-terminal-exec -> kitty"

    gsettings set org.gnome.TextEditor draw-spaces "['space', 'tab', 'trailing']"
    echo "    gnome-text-editor: show whitespace"
}

get_wallpapers() {
    local reply
    read -p "Do you want to get wallpapers? (y/N): " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        info "Getting wallpapers"
        mkdir -p "$HOME/Pictures"
        \cp -rn "$REPO_ROOT/wallpapers" "$HOME/Pictures"
    fi
}

# Ensure hyprlock background points to a valid file on the current system
normalize_hyprlock_wallpaper() {
    local conf="$HOME/.config/hypr/hyprlock.conf" current candidate
    if [ ! -f "$conf" ]; then
        return 0
    fi
    current="$(sed -n 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*//p' "$conf" | head -1)"
    if [ -z "$current" ] || [ -f "$current" ]; then
        return 0
    fi

    candidate="$HOME/Pictures/wallpapers/$(basename "$current")"
    if [ ! -f "$candidate" ]; then
        candidate="$(find "$HOME/Pictures/wallpapers" -maxdepth 1 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
               -o -iname '*.webp' \) 2>/dev/null | sort | head -1 || true)"
    fi
    if [ -z "$candidate" ] || [ ! -f "$candidate" ]; then
        echo "    hyprlock background: $current is missing and no wallpaper was found"
        return 0
    fi

    sed -i "s|^\([[:space:]]*\)path = .*|\1path = ${candidate//&/\\&}|" "$conf"
    echo "    hyprlock background -> $candidate"
}

# Reload Hyprland session and restart background UI daemons
reload_session() {
    if ! command -v hyprctl >/dev/null 2>&1 || ! hyprctl version >/dev/null 2>&1; then
        info "Not reloading"
        echo "    Hyprland is not running -- the new config applies at next login."
        return 0
    fi

    info "Reloading the session"
    hyprctl reload >/dev/null 2>&1 || true
    echo "    hyprctl reload"

    killall quickshell >/dev/null 2>&1 || true
    sleep 1
    setsid quickshell >/dev/null 2>&1 &
    disown
    echo "    quickshell restarted (bar + SUPER+SPACE / V / W overlays)"

    if command -v hypridle >/dev/null 2>&1; then
        killall hypridle >/dev/null 2>&1 || true
        sleep 0.5
        setsid hypridle >/dev/null 2>&1 &
        disown
        echo "    hypridle restarted (idle and lock rules)"
    fi

    check_notification_owner
}

# Verify quickshell claimed org.freedesktop.Notifications
check_notification_owner() {
    command -v busctl >/dev/null 2>&1 || return 0

    local i owner=""
    for i in 1 2 3 4 5 6 7 8 9 10; do
        owner="$(busctl --user status org.freedesktop.Notifications 2>/dev/null \
                 | sed -n 's/^Comm=//p' | head -1 || true)"
        if [ -n "$owner" ]; then
            break
        fi
        sleep 0.5
    done

    case "$owner" in
        quickshell|qs)
            echo "    notifications: owned by the bar ($owner)" ;;
        "")
            echo "    WARNING: nothing owns org.freedesktop.Notifications yet."
            echo "             The bar may still be starting; check with:"
            echo "               busctl --user status org.freedesktop.Notifications" ;;
        *)
            echo "    WARNING: org.freedesktop.Notifications is held by '$owner',"
            echo "             not the bar -- its notification module will stay empty."
            echo "             Stop that daemon and restart the bar:"
            echo "               pkill -x $owner && killall quickshell && setsid quickshell &" ;;
    esac
}

# Reverse direction: live system -> repo, for review and commit
pull_configs() {
    info "Pulling live configs into $SCRIPT_DIR"
    local c
    for c in "${CONFIGS[@]}"; do
        if [ ! -d "$HOME/.config/$c" ]; then
            echo "    skip $c (not deployed)"
            continue
        fi
        \cp -rf "$HOME/.config/$c" "$SCRIPT_DIR"
        echo "    $c"
    done
    if [ -d /usr/share/sddm/themes/voidsddm ]; then
        \cp -rf /usr/share/sddm/themes/voidsddm "$SCRIPT_DIR"
        echo "    voidsddm"
    fi
    if [ -d /etc/sddm.conf.d ]; then
        \cp -rf /etc/sddm.conf.d "$SCRIPT_DIR"
        echo "    sddm.conf.d"
    fi

    cat <<EOF

Pulled. Note this ADDS and OVERWRITES files but never deletes, and it brings
this machine's hyprlock background into the repo. Review before committing:

    git -C $REPO_ROOT status
    git -C $REPO_ROOT diff
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    case "${1:-}" in
        --help|-h) usage; exit 0 ;;
        --pull)    pull_configs; exit 0 ;;
        "")        ;;
        *)         echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac

    install_packages

    migrate_audio_icons
    save_lock_wallpaper

    deploy_configs
    remove_orphans
    retire_swaync
    restore_lock_wallpaper

    fix_permissions
    check_lid_handling
    apply_system_tweaks
    apply_gtk_theme
    get_wallpapers
    normalize_hyprlock_wallpaper
    reload_session
    info "Done."
}

main "$@"
