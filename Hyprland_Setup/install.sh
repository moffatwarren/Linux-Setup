#!/bin/bash
# Deploy this repo's configs to the live system (and pull live changes back).
# See CLAUDE.md at the repo root for the full workflow.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Config directories: Hyprland_Setup/<name>  ->  ~/.config/<name>
# Add a new app config by adding its directory name here. A name with no
# matching directory is skipped with a warning rather than aborting.
# ---------------------------------------------------------------------------
CONFIGS=(fastfetch fish hypr kitty nvim quickshell rofi swappy swaync waybar weathr)

PACMAN_PKGS=(
    kitty hyprland waybar quickshell hyprlock hypridle awww ttf-font-awesome swaync
    ttf-jetbrains-mono-nerd swappy btop fastfetch thunar tumbler slurp cliphist grim nwg-look rofi
    gvfs gvfs-smb samba nvim mpv imv brightnessctl playerctl blueman gnome-text-editor swayimg imagemagick
    thunar-archive-plugin xarchiver unzip net-tools localsend spotify-launcher
    tesseract tesseract-data-eng speedtest-cli brave-origin-bin paru
    # Called by the deployed scripts/bars rather than by install.sh itself:
    # jq (tailscale.sh), libpulse+wireplumber (pactl/wpctl in the audio and
    # volume scripts), pavucontrol (audio right-click), power-profiles-daemon
    # (the power profile module), networkmanager (the network module + nmtui).
    jq libpulse wireplumber pavucontrol power-profiles-daemon networkmanager
)
PARU_PKGS=(pokemon-colorscripts-git rustdesk-bin teams-for-linux vscodium-bin weathr-bin)

# ---------------------------------------------------------------------------
# Machine-specific values preserved across an update.
#   <path under ~/.config> | <regex> | <prompt group> | <handler>
# Handlers: "line"  = whole line matching <regex> is captured and restored.
#           "icons" = the "pulseaudio" -> "format-icons" block (<regex> unused).
# Fields split on "|", so a regex must not contain a literal "|".
#
# NOTE: "line" restores EVERY matching line. BUILT_IN_SINK is also assigned
# indented inside the toggle logic, so it is anchored to column 0.
# ---------------------------------------------------------------------------
PRESERVE=(
    "waybar/scripts/audio-output-toggle.sh|^BUILT_IN_SINK\s*=|audio|line"
    "waybar/scripts/audio-output-toggle.sh|^\s*HEADPHONE_SINK\s*=|audio|line"
    "waybar/scripts/audio-output-toggle.sh|^\s*SPEAKER_SINK\s*=|audio|line"
    "waybar/scripts/audio-output-toggle.sh|^\s*BLUETOOTH_SINK\s*=|audio|line"
    "waybar/config|-|audio|icons"
    "hypr/modules/config.lua|^\s*config\.mainMonitor\s*=|machine|line"
    "hypr/modules/config.lua|^\s*config\.bar\s*=|machine|line"
)

declare -A GROUP_PROMPT=(
    [audio]="Overwrite audio sink values and volume icons?"
    [machine]="Overwrite monitor and bar selection?"
)

declare -A GROUP_MODE=()   # group -> "preserve" when the live value is kept
declare -A PRESERVED=()    # "<rel>|<regex>" -> captured value

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

usage() {
    cat <<EOF
Usage: install.sh [OPTION]

  (no option)   Install packages and deploy this repo's configs to the live
                system. Handles both first-time install and routine updates.
  --pull        Copy the LIVE configs back into this repo so changes made on
                the machine can be reviewed and committed. Does not commit.
  --help        Show this message.
EOF
}

preserve_groups() { printf '%s\n' "${PRESERVE[@]}" | cut -d'|' -f3 | awk '!seen[$0]++'; }
preserve_files()  { printf '%s\n' "${PRESERVE[@]}" | cut -d'|' -f1 | awk '!seen[$0]++'; }

group_has_live_file() {
    local group="$1" entry rel regex g handler
    for entry in "${PRESERVE[@]}"; do
        IFS='|' read -r rel regex g handler <<<"$entry"
        if [ "$g" = "$group" ] && [ -f "$HOME/.config/$rel" ]; then
            return 0
        fi
    done
    return 1
}

# Ask, per group, whether to overwrite the machine-specific values it covers.
prompt_preserve_groups() {
    local group reply groups=()
    # Read the list into an array first: a `while read < <(...)` loop would
    # redirect stdin, and the `read -p` below would consume the group list
    # instead of the user's answer.
    mapfile -t groups < <(preserve_groups)
    for group in "${groups[@]}"; do
        if ! group_has_live_file "$group"; then
            continue
        fi
        read -p "${GROUP_PROMPT[$group]} (y/N): " reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            GROUP_MODE[$group]=preserve
        fi
    done
}

# Capture live values BEFORE the configs get overwritten.
capture_preserved() {
    local entry rel regex group handler live
    for entry in "${PRESERVE[@]}"; do
        IFS='|' read -r rel regex group handler <<<"$entry"
        if [ "${GROUP_MODE[$group]:-overwrite}" != preserve ]; then
            continue
        fi
        live="$HOME/.config/$rel"
        if [ ! -f "$live" ]; then
            continue
        fi
        case "$handler" in
            line)  PRESERVED["$rel|$regex"]="$(grep -E "$regex" "$live" || true)" ;;
            icons) PRESERVED["$rel|$regex"]="$(python3 "$SCRIPT_DIR/install_lib/waybar_format_icons.py" get "$live")" ;;
        esac
    done
}

# Write captured values back AFTER the configs have been overwritten.
restore_preserved() {
    local rel entry r regex group handler key args files=()
    mapfile -t files < <(preserve_files)
    for rel in "${files[@]}"; do
        if [ ! -f "$HOME/.config/$rel" ]; then
            continue
        fi
        args=()
        for entry in "${PRESERVE[@]}"; do
            IFS='|' read -r r regex group handler <<<"$entry"
            if [ "$r" != "$rel" ]; then
                continue
            fi
            key="$r|$regex"
            if [ -z "${PRESERVED[$key]:-}" ]; then
                continue
            fi
            case "$handler" in
                line)  args+=("$regex" "${PRESERVED[$key]}") ;;
                icons) python3 "$SCRIPT_DIR/install_lib/waybar_format_icons.py" \
                           set "$HOME/.config/$rel" "${PRESERVED[$key]}" ;;
            esac
        done
        if [ "${#args[@]}" -gt 0 ]; then
            python3 "$SCRIPT_DIR/install_lib/replace_line.py" "$HOME/.config/$rel" "${args[@]}"
        fi
    done
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
install_packages() {
    info "Installing packages"
    sudo pacman -S --noconfirm --needed "${PACMAN_PKGS[@]}"
    paru -S --noconfirm --skipreview --needed "${PARU_PKGS[@]}"
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
    sudo \cp -rf "$SCRIPT_DIR/voidsddm" /usr/share/sddm/themes
    sudo \cp -rf "$SCRIPT_DIR/sddm.conf.d" /etc
    echo "    voidsddm + sddm.conf.d (system)"
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

# Steps from the top-level *.txt notes that can actually be automated.
# Each is optional and idempotent; the interactive tail of each is printed.
first_install_extras() {
    info "First-install setup"
    sudo systemctl enable --now avahi-daemon
    sudo ln -sf /usr/bin/kitty /usr/bin/xdg-terminal-exec
    gsettings set org.gnome.TextEditor draw-spaces "['space', 'tab', 'trailing']"

    local reply name email
    if ! git config --global user.name >/dev/null 2>&1; then
        read -p "  Set global git identity now? (y/N): " reply
        if [[ "$reply" =~ ^[Yy]$ ]]; then
            read -p "    git user.name:  " name
            read -p "    git user.email: " email
            if [ -n "$name" ];  then git config --global user.name  "$name";  fi
            if [ -n "$email" ]; then git config --global user.email "$email"; fi
            git config --global credential.helper store
        fi
    fi

    # tailscale_commands.txt -- installed from the Arch repo rather than the
    # upstream `curl | sh`, which is meant for distros without a package.
    read -p "  Install and enable Tailscale? (y/N): " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        sudo pacman -S --noconfirm --needed tailscale
        sudo systemctl enable --now tailscaled
        # --operator=$USER is what lets waybar/scripts/tailscale.sh run without sudo
        echo "    Authenticate with:"
        echo "      sudo tailscale up --accept-routes --exit-node-allow-lan-access --operator=$USER"
    fi

    # pia_install.txt
    read -p "  Install PIA VPN? (y/N): " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        paru -S --noconfirm --skipreview --needed piavpn-bin
        sudo systemctl enable --now piavpn.service
        echo "    Open the PIA app and log in to finish setup."
    fi
}

get_wallpapers() {
    local reply
    read -p "Do you want to get wallpapers? (y/N): " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        info "Getting wallpapers"
        \cp -rn "$REPO_ROOT/wallpapers" "$HOME/Pictures"
    fi
}

# Reverse direction: live system -> repo, for review and commit.
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
machine-specific values (audio sinks, mainMonitor, bar choice) into the repo.
Review before committing:

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

    local resp_install
    read -p "Is this the first install (y/N): " resp_install
    if [[ "$resp_install" =~ ^[Yy]$ ]]; then
        first_install_extras
    else
        prompt_preserve_groups
        capture_preserved
    fi

    deploy_configs

    if [[ ! "$resp_install" =~ ^[Yy]$ ]]; then
        info "Restoring machine-specific values"
        restore_preserved
    fi

    fix_permissions
    get_wallpapers
    info "Done."
}

main "$@"
