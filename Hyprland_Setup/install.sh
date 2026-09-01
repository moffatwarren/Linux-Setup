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
CONFIGS=(fastfetch fish gtk-3.0 gtk-4.0 hypr kitty nvim quickshell rofi swappy swaync weathr)

PACMAN_PKGS=(
    kitty hyprland quickshell hyprlock hypridle awww ttf-font-awesome swaync
    ttf-jetbrains-mono-nerd swappy btop fastfetch thunar tumbler slurp cliphist grim nwg-look rofi
    gvfs gvfs-smb samba nvim mpv imv brightnessctl playerctl blueman gnome-text-editor swayimg imagemagick
    thunar-archive-plugin xarchiver unzip net-tools localsend spotify-launcher
    tesseract tesseract-data-eng speedtest-cli brave-origin-bin paru
    # GTK theming (thunar, the file chooser, gnome-text-editor). adw-gtk-theme
    # owns adw-gtk3-dark and cantarell-fonts the font, both named by
    # gtk-3.0/settings.ini; papirus-icon-theme is what Papirus-Dark resolves to.
    adw-gtk-theme cantarell-fonts papirus-icon-theme
    # Called by the deployed scripts/bars rather than by install.sh itself:
    # jq (tailscale.sh), libpulse+wireplumber (pactl/wpctl in the audio and
    # volume scripts), pavucontrol (audio right-click), power-profiles-daemon
    # (the power profile module), networkmanager (the network module + nmtui),
    # qt6-imageformats (webp/avif thumbnails in the SUPER+W wallpaper picker --
    # Qt ships only jpg/png/gif out of the box), libnotify (notify-send in the
    # OSD and wallpaper scripts) and wl-clipboard (wl-copy/wl-paste in the
    # clipboard binds). The last two also arrive as dependencies of thunar and
    # cliphist, but a script calling them directly should not rely on that.
    jq libpulse wireplumber pavucontrol power-profiles-daemon networkmanager
    qt6-imageformats libnotify wl-clipboard
    # Needed by install.sh itself rather than by anything it deploys: sddm owns
    # /usr/share/sddm/themes (deploy_configs copies voidsddm into it) and avahi
    # owns the avahi-daemon unit first_install_extras enables. Both happen to be
    # present on a stock CachyOS install; neither is guaranteed on plain Arch,
    # and under `set -e` a missing one aborts the run part-way through.
    sddm avahi
)
# papirus-folders-catppuccin-git both *provides* and *conflicts with* plain
# papirus-folders, so listing the two together fails the whole transaction.
PARU_PKGS=(
    pokemon-colorscripts-git rustdesk-bin teams-for-linux vscodium-bin weathr-bin
    papirus-folders-catppuccin-git
)

# ---------------------------------------------------------------------------
# Machine-specific values preserved across an update.
#   <path under ~/.config> | <regex> | <prompt group> | <handler>
# Handler: "line" = whole line matching <regex> is captured and restored.
# Fields split on "|", so a regex must not contain a literal "|".
#
# NOTE: "line" restores EVERY matching line. BUILT_IN_SINK is also assigned
# indented inside the toggle logic, so it is anchored to column 0.
# ---------------------------------------------------------------------------
PRESERVE=(
    "hypr/hyprlock.conf|^\s*path\s*=|wallpaper|line"
    "hypr/scripts/audio-output-toggle.sh|^BUILT_IN_SINK\s*=|audio|line"
    "hypr/scripts/audio-output-toggle.sh|^\s*HEADPHONE_SINK\s*=|audio|line"
    "hypr/scripts/audio-output-toggle.sh|^\s*SPEAKER_SINK\s*=|audio|line"
    "hypr/scripts/audio-output-toggle.sh|^\s*BLUETOOTH_SINK\s*=|audio|line"
    "hypr/modules/config.lua|^\s*config\.mainMonitor\s*=|machine|line"
)

declare -A GROUP_PROMPT=(
    [audio]="Overwrite audio sink values?"
    [machine]="Overwrite monitor selection?"
)

# Groups kept without asking: on anything but a first install the live value
# always wins. The hyprlock wallpaper is a personal choice, not a fix to ship.
NO_PROMPT_GROUPS=(wallpaper)

# Files that moved between releases, as "<old path>|<new path>" under ~/.config.
# On a machine still running the previous layout the new path does not exist
# yet, so its machine-specific values would never be captured and would be
# silently replaced by whatever this repo has committed. Seeding the new path
# from the old one before the capture step keeps them.
LEGACY_MOVES=(
    "waybar/scripts/audio-output-toggle.sh|hypr/scripts/audio-output-toggle.sh"
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

group_is_no_prompt() {
    local group="$1" g
    for g in "${NO_PROMPT_GROUPS[@]}"; do
        if [ "$g" = "$group" ]; then
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
        if group_is_no_prompt "$group"; then
            GROUP_MODE[$group]=preserve
            continue
        fi
        read -p "${GROUP_PROMPT[$group]} (y/N): " reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            GROUP_MODE[$group]=preserve
        fi
    done
}

# Carry values over from a path that moved, so the capture below can find them.
migrate_legacy_paths() {
    local entry old new
    for entry in "${LEGACY_MOVES[@]}"; do
        IFS='|' read -r old new <<<"$entry"
        if [ -f "$HOME/.config/$old" ] && [ ! -f "$HOME/.config/$new" ]; then
            mkdir -p "$(dirname "$HOME/.config/$new")"
            \cp -f "$HOME/.config/$old" "$HOME/.config/$new"
            echo "    carried over $old -> $new"
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
        PRESERVED["$rel|$regex"]="$(grep -E "$regex" "$live" || true)"
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
            args+=("$regex" "${PRESERVED[$key]}")
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
    # sddm is in PACMAN_PKGS, but its theme directory only exists if the package
    # ships one. Copying into a missing directory fails, and under `set -e` that
    # aborts the run with the ~/.config half of the deploy already done.
    sudo mkdir -p /usr/share/sddm/themes
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

# GTK theming that is not a file under ~/.config, so deploy_configs cannot do
# it. Everything here is idempotent and runs on every deploy, not just a first
# install: it is how a new machine gets the folder colour at all, and gsettings
# is per-user state that a fresh account does not carry.
apply_gtk_theme() {
    info "Applying GTK theme"

    # gtk-3.0/gtk.css recolours adw-gtk3-dark, but the folder icons are images
    # and CSS cannot touch them -- they are the file manager's dominant colour.
    # Call it WITHOUT sudo: it re-execs itself under sudo when the theme lives
    # in /usr/share/icons, forwarding the USER_HOME/XDG_DATA_DIRS that a
    # per-user Papirus copy needs. (papirus-folders-catppuccin-git also ships a
    # pacman hook that re-applies the colour after a papirus-icon-theme upgrade,
    # so this is only responsible for setting it the first time.)
    #
    # The `if` is what keeps a cosmetic step from aborting the whole deploy:
    # papirus-folders calls `fatal` for a colour the installed theme does not
    # carry, and its sudo re-exec fails if the password prompt is declined.
    # Either would, under `set -e`, stop the run here -- with the configs
    # already copied but get_wallpapers and normalize_hyprlock_wallpaper still
    # to go. Icons are not worth a half-finished install.
    if ! command -v papirus-folders >/dev/null 2>&1; then
        echo "    skip papirus-folders (not installed)"
    elif papirus-folders -C cat-mocha-blue --theme Papirus-Dark >/dev/null 2>&1; then
        echo "    Papirus-Dark folders -> cat-mocha-blue"
    else
        echo "    WARNING: papirus-folders failed -- folders keep the stock Papirus blue."
        echo "             Everything else is themed. Retry by hand with:"
        echo "               papirus-folders -C cat-mocha-blue --theme Papirus-Dark"
    fi

    # settings.ini is only read by GTK3 apps; xdg-desktop-portal-gtk and every
    # GTK4/libadwaita app read gsettings instead, so without this the portal file
    # chooser thunar opens is still stock Adwaita. Keep the values in step with
    # gtk-3.0/settings.ini by hand. Unguarded on purpose: the schema ships in
    # gsettings-desktop-schemas, which arrives with gvfs (in PACMAN_PKGS), and
    # dconf is a hard dependency of gtk3/gtk4 -- so on any machine this script
    # has got this far on, both exist and a failure here is worth aborting for.
    gsettings set org.gnome.desktop.interface gtk-theme    "adw-gtk3-dark"
    gsettings set org.gnome.desktop.interface icon-theme   "Papirus-Dark"
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
    gsettings set org.gnome.desktop.interface font-name    "Cantarell 11"
    echo "    gsettings: adw-gtk3-dark / Papirus-Dark / prefer-dark"

    # GTK reads its stylesheet once at startup, and thunar stays resident as a
    # daemon after its last window closes -- so on an update the new colours
    # would not appear until the next logout, which reads as "the deploy did
    # nothing". Quitting it means the next launch picks them up. This closes any
    # open thunar windows; `|| true` because it exits non-zero when none is
    # running, which is the normal case.
    if command -v thunar >/dev/null 2>&1; then
        thunar -q >/dev/null 2>&1 || true
    fi
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
        # --operator=$USER is what lets hypr/scripts/tailscale.sh run without sudo
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
        # `cp -r src dest` creates dest AS a copy of src when dest is missing,
        # so without this the images land directly in ~/Pictures. The picker
        # (WallpaperPicker.qml) and wallpaper-random.sh both read
        # ~/Pictures/wallpapers, and would find nothing. xdg-user-dirs usually
        # creates ~/Pictures, but a fresh machine may not have it yet.
        mkdir -p "$HOME/Pictures"
        \cp -rn "$REPO_ROOT/wallpapers" "$HOME/Pictures"
    fi
}

# The committed hyprlock background is an absolute path, so it names the $HOME
# of whichever machine last committed it. A first install preserves nothing, so
# on a machine with a different username that path does not resolve and the lock
# screen comes up with no background at all. Re-point it at the same file under
# this machine's $HOME, and fall back to any wallpaper if that name is gone.
#
# Only the seed matters here: wallpaper-set.sh owns this line from then on, and
# PRESERVE (group `wallpaper`, in NO_PROMPT_GROUPS) keeps it across later runs.
# Deliberately does not go through wallpaper-set.sh, which needs the awww daemon
# up -- during an install it is not.
normalize_hyprlock_wallpaper() {
    local conf="$HOME/.config/hypr/hyprlock.conf" current candidate
    if [ ! -f "$conf" ]; then
        return 0
    fi
    current="$(sed -n 's/^[[:space:]]*path[[:space:]]*=[[:space:]]*//p' "$conf" | head -1)"
    # Nothing set, or the committed path resolves here: leave it alone.
    if [ -z "$current" ] || [ -f "$current" ]; then
        return 0
    fi

    candidate="$HOME/Pictures/wallpapers/$(basename "$current")"
    if [ ! -f "$candidate" ]; then
        # `|| true`: the wallpaper prompt is optional, so the directory may not
        # exist at all. find then exits non-zero, and pipefail would make the
        # whole assignment fail the script rather than just yielding "".
        candidate="$(find "$HOME/Pictures/wallpapers" -maxdepth 1 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
               -o -iname '*.webp' \) 2>/dev/null | sort | head -1 || true)"
    fi
    if [ -z "$candidate" ] || [ ! -f "$candidate" ]; then
        echo "    hyprlock background: $current is missing and no wallpaper was found"
        return 0
    fi

    # `&` is the one character sed expands in a replacement, as in
    # wallpaper-set.sh, which writes this same line.
    sed -i "s|^\([[:space:]]*\)path = .*|\1path = ${candidate//&/\\&}|" "$conf"
    echo "    hyprlock background -> $candidate"
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
machine-specific values (audio sinks, mainMonitor, hyprlock wallpaper) into the
repo. Review before committing:

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
        migrate_legacy_paths
        prompt_preserve_groups
        capture_preserved
    fi

    deploy_configs

    if [[ ! "$resp_install" =~ ^[Yy]$ ]]; then
        info "Restoring machine-specific values"
        restore_preserved
    fi

    fix_permissions
    apply_gtk_theme
    get_wallpapers
    # After get_wallpapers, so a first install has the images to point at.
    normalize_hyprlock_wallpaper
    info "Done."
}

main "$@"
