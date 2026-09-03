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
CONFIGS=(btop fastfetch fish gtk-3.0 gtk-4.0 hypr kitty nvim quickshell swappy weathr)

# ---------------------------------------------------------------------------
# Paths under ~/.config that an EARLIER release of this repo deployed and this
# one no longer ships. `deploy_configs` copies with `cp -rf`, which adds and
# overwrites but never deletes, so without this list a machine upgrading from an
# older layout keeps them for ever -- dead configs that still look live.
#
# Each entry is removed with `rm -rf`, so add only paths this repo itself put
# there. A directory is fine; a bare name would delete a whole ~/.config subtree.
# ---------------------------------------------------------------------------
ORPHANS=(
    # rofi drew the app launcher, the clipboard list and the wallpaper picker.
    # All three are quickshell overlays now (quickshell/OverlayPanel.qml) and
    # nothing is bound to rofi any more, so its config goes with it. The rofi
    # *package* is left installed; this script does not uninstall anything.
    rofi
    hypr/scripts/clipboard-menu.sh
    hypr/scripts/wallpaper-selector.sh
    hypr/modules/utils/wallpaper_utils.lua
    # The GTK theme these replaced; deploying gtk.css drops the @import that
    # referenced it, but the file itself stays behind.
    gtk-3.0/noctalia.css
    gtk-4.0/noctalia.css
    # swaync was the notification daemon. Quickshell is the notification server
    # itself now (quickshell/NotificationService.qml) and only one process can
    # hold org.freedesktop.Notifications, so leaving swaync's config behind
    # would just be a config for a daemon nothing starts. Nothing uninstalls
    # the swaync *package*; this script only ever installs.
    swaync
    # The StatusNotifierItem tray and the DBus menu it drew. Dropped from the
    # bar again; blueman's own applet is the bluetooth UI, and BluetoothPill is
    # back. Nothing deployed references these, but cp -rf never removes.
    quickshell/TrayPill.qml
    quickshell/TrayMenu.qml
    quickshell/TrayMenuItems.qml
)

PACMAN_PKGS=(
    kitty hyprland quickshell hyprlock hypridle awww ttf-font-awesome
    ttf-jetbrains-mono-nerd swappy btop fastfetch thunar tumbler slurp cliphist grim nwg-look
    # wf-recorder is the SUPER+CTRL+S screen recorder (hypr/scripts/screen-record.sh);
    # it reuses the slurp above for the region select.
    wf-recorder
    gvfs gvfs-smb samba nvim mpv imv brightnessctl playerctl blueman gnome-text-editor swayimg imagemagick
    thunar-archive-plugin xarchiver unzip net-tools localsend spotify-launcher
    speedtest-cli brave-origin-bin paru
    # SUPER+ALT+S (binds.lua) is OCR-to-clipboard: grim a region, read the
    # text out of it, wl-copy that. The language data is a separate package
    # and tesseract without it exits with "Error opening data file", so the
    # keybind would silently copy nothing -- neither of these is optional.
    tesseract tesseract-data-eng
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
    # OSD and wallpaper scripts -- the bar renders them, but the scripts still
    # send them the same way), and cliphist + wl-clipboard + imagemagick,
    # which are between them the whole SUPER+V clipboard history: the store, the
    # wl-copy that puts an entry back, and the `magick` that makes its thumbnail.
    # Some of these also arrive as dependencies of thunar and cliphist, but a
    # script calling them directly should not rely on that.
    jq libpulse wireplumber pavucontrol power-profiles-daemon networkmanager
    qt6-imageformats libnotify wl-clipboard
    # curl is what weather-forecast.sh, pia-region.sh and public-ip.sh all fetch
    # with. It is a hard dependency of pacman itself, so it cannot actually be
    # missing here -- listed anyway, because a script calling a binary directly
    # should not rely on arriving as somebody else's dependency.
    curl
    # Needed by install.sh itself rather than by anything it deploys: sddm owns
    # /usr/share/sddm/themes (deploy_configs copies voidsddm into it) and avahi
    # owns the avahi-daemon unit apply_system_tweaks enables. Both happen to be
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
# There is no machine-specific value table any more, and no prompt to go with it.
#
# This used to be the subtle part of the script: PRESERVE named lines in deployed
# configs that were true only of this hardware, and every deploy captured them
# before the copy and wrote them back after, one y/N prompt per group. Three
# things lived there, and each was removed by making the value answerable rather
# than by defending it:
#
#   audio sinks -- which output SUPER+O steps to, and the glyph each one draws,
#                  are chosen in the bar's audio menu and persisted to
#                  ~/.cache/quickshell-audio.json (quickshell/AudioService.qml).
#                  User state under ~/.cache, which a deploy never touches.
#   mainMonitor -- the laptop's built-in panel is now identified by its DRM
#                  connector name (hypr/scripts/monitor-toggle.sh). Nothing to
#                  set: the kernel only ever calls a built-in panel eDP/LVDS/DSI.
#                  The committed value was stale on the machine it came from,
#                  which is the argument against hand-set hardware names in one
#                  line.
#   hyprlock bg -- still a real per-machine value, but the only one, so it is a
#                  named pair of functions (save/restore_lock_wallpaper) rather
#                  than a table, a handler dispatch and a Python helper. That
#                  helper, install_lib/replace_line.py, went with the table.
#
# Anything hardware-specific added from here should follow the same order: make
# it discoverable at runtime, then store what the user chose outside ~/.config,
# and only then consider preserving a committed line.
# ---------------------------------------------------------------------------


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

# One-shot: carry this machine's audio roles into the bar's audio menu.
#
# hypr/scripts/audio-output-toggle.sh used to declare HEADPHONE_SINK and
# BLUETOOTH_SINK, and the bar read them to decide which glyph an output got.
# Both are now a per-sink choice in the menu, persisted to the cache file below.
# The catch is that this repo no longer ships those declarations, so
# deploy_configs is about to overwrite the ONLY record of which sink is which on
# a machine upgrading from the old layout -- and unlike everything else that
# happens on an update, nothing would say so. The answer is not recoverable
# afterwards, and it is not guessable: a sink's role cannot be inferred from its
# name, which is why those variables existed.
#
# So: read them out before the copy, and seed the icon of any sink that does not
# already have one. Runs before deploy_configs for that reason.
#
# Self-limiting rather than flagged: after one update the deployed script has no
# such declarations, so the grep finds nothing and this is a no-op for ever
# after. It also never overwrites an icon already chosen in the menu.
#
# The cache file is normally written only by the bar (AudioService.qml), and on
# an upgrading machine that is safe here: the bar still running is the OLD one,
# which has no AudioService and never touches this file. reload_session restarts
# it at the end of main(), so the new bar reads what this wrote.
migrate_audio_icons() {
    local legacy="" state="$HOME/.cache/quickshell-audio.json" tmp
    local candidate headphone="" bluetooth=""

    # hypr/ first, then the waybar-era path -- the same two LEGACY_MOVES named,
    # so a machine that skipped a generation is still covered.
    for candidate in "$HOME/.config/hypr/scripts/audio-output-toggle.sh" \
                     "$HOME/.config/waybar/scripts/audio-output-toggle.sh"; do
        if [ -f "$candidate" ] && grep -qE '^[[:space:]]*HEADPHONE_SINK[[:space:]]*=' "$candidate"; then
            legacy="$candidate"
            break
        fi
    done
    # No old-style script: a new machine, or one already migrated.
    [ -n "$legacy" ] || return 0

    command -v jq >/dev/null 2>&1 || return 0

    # sed rather than sourcing the file, which would run it.
    headphone="$(sed -nE 's/^[[:space:]]*HEADPHONE_SINK[[:space:]]*=[[:space:]]*"?([^"]*)"?.*/\1/p' \
                 "$legacy" | head -1)"
    bluetooth="$(sed -nE 's/^[[:space:]]*BLUETOOTH_SINK[[:space:]]*=[[:space:]]*"?([^"]*)"?.*/\1/p' \
                 "$legacy" | head -1)"

    # BUILT_IN_SINK and SPEAKER_SINK are deliberately not carried over. Their
    # icon would be `speaker`, which differs from the default `volume` only in
    # looks, and BUILT_IN_SINK is the one most likely to still hold the value
    # this repo shipped rather than anything true about this machine -- seeding
    # it would add a phantom "unplugged" row for a sink that never existed here.
    [ -n "$headphone" ] || [ -n "$bluetooth" ] || return 0

    info "Carrying audio icons into the bar's audio menu"

    # ~/.cache exists on any machine this can run on, but a failed redirect
    # here would abort the whole deploy under `set -e`, before deploy_configs.
    mkdir -p "$(dirname "$state")"
    [ -f "$state" ] || printf '{ "outputs": [] }\n' > "$state"

    tmp="$(mktemp)"
    if jq --arg hp "$headphone" --arg bt "$bluetooth" '
          # Add a record for a sink we have never seen, or fill in the icon of
          # one that has no choice yet. Never overwrite a choice already made.
          def seed($name; $icon):
            if $name == "" then .
            elif [.outputs[]?.name] | index($name) then
              .outputs |= map(if .name == $name and (.icon // "") == ""
                              then .icon = $icon else . end)
            else .outputs += [{ name: $name, description: $name,
                                enabled: true, icon: $icon }]
            end;
          (.outputs //= []) | seed($hp; "headphones") | seed($bt; "bluetooth")
       ' "$state" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$state"
        [ -n "$headphone" ] && echo "    headphones -> $headphone"
        [ -n "$bluetooth" ] && echo "    bluetooth  -> $bluetooth"
        echo "    change either from the audio menu (left-click the audio pill)"
    else
        rm -f "$tmp"
        echo "    WARNING: could not update $state -- pick the icons from the"
        echo "             audio menu instead (left-click the audio pill)."
    fi
}

# The lock screen background is the one value still true only of this machine:
# SUPER+W writes the chosen wallpaper into hyprlock.conf (wallpaper-set.sh), and
# deploy_configs is about to copy the committed one over it. Captured before and
# written back after -- the whole of what PRESERVE used to do generically.
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
    # Only if it still resolves. A path from a machine that has since had the
    # file deleted would leave a lock screen with no background at all, and
    # normalize_hyprlock_wallpaper (which runs later) can do better than that.
    [ -f "$LOCK_WALLPAPER" ] || return 0
    # `&` is the one character sed expands in a replacement, as in
    # wallpaper-set.sh, which writes this same line.
    sed -i "s|^\\([[:space:]]*\\)path = .*|\\1path = ${LOCK_WALLPAPER//&/\\&}|" "$conf"
    echo "    kept the live hyprlock background: $LOCK_WALLPAPER"
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

# Several bar modules are nothing but a glyph -- the network icons, the audio
# icons, the notification bell, the weather conditions -- and those glyphs are
# Material Design Icons from Nerd Fonts **v3**, which lives at U+F0000 and above.
# v2 was entirely inside the BMP and has nothing at those codepoints at all, so
# on the old font those modules draw tofu or, worse, nothing: `Pill` hides a
# module whose label came out empty, so the symptom can be a module that has
# simply vanished rather than one that looks wrong.
#
# ttf-jetbrains-mono-nerd (PACMAN_PKGS) is v3 on any current Arch and `pacman -S
# --needed` upgrades an out-of-date package, so this only fires for a font
# installed by hand that shadows the packaged one, or a package database old
# enough that pacman had nothing newer to offer. It warns rather than aborting:
# a wrong-looking bar is not a reason to leave a deploy half-done.
#
# Probed by codepoint rather than by package version, because the version is a
# proxy and the glyph is the thing that actually has to be there.
check_nerd_font() {
    command -v fc-list >/dev/null 2>&1 || return 0

    local cp missing=()
    # md-ethernet (NetworkPill) and md-volume-high (AudioPill): one from each of
    # the modules whose entire label is a single v3 glyph.
    for cp in f0200 f057e; do
        if ! fc-list ":charset=$cp:family=JetBrainsMono Nerd Font" 2>/dev/null | grep -q .; then
            missing+=("U+${cp^^}")
        fi
    done

    if [ "${#missing[@]}" -eq 0 ]; then
        echo "    nerd font: Nerd Fonts v3 glyphs present"
        return 0
    fi

    echo "    WARNING: JetBrainsMono Nerd Font is missing ${missing[*]}."
    echo "             Those are Nerd Fonts v3 codepoints, so this font is v2 --"
    echo "             the icon-only bar modules (network, audio, notifications,"
    echo "             weather) will draw tofu or drop out of the bar entirely."
    echo "             Try, in order:"
    echo "               fc-cache -f                                  # just a cold cache"
    echo "               sudo pacman -Syu ttf-jetbrains-mono-nerd     # stale package"
    echo "               fc-list | grep -i 'jetbrainsmono nerd'       # a hand-installed v2 shadowing it"
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

# Delete what an older release of this repo deployed and this one has dropped.
# `cp -rf` in deploy_configs only adds and overwrites, so a machine upgrading
# from a previous layout would otherwise keep every retired config for ever.
# Runs on a first install too, where it simply finds nothing.
remove_orphans() {
    info "Removing configs this release no longer ships"
    local p target found=0
    for p in "${ORPHANS[@]}"; do
        # An empty entry would expand to ~/.config itself. Cheap guard, and the
        # only thing standing between a typo in ORPHANS and a wiped config dir.
        [ -n "$p" ] || continue
        # A path this repo still ships is not an orphan, whatever the list says.
        # Without this a stale entry silently deletes what deploy_configs just
        # wrote, one step earlier, and the config simply stops existing.
        if [ -e "$SCRIPT_DIR/$p" ]; then
            echo "    skip $p (this repo still ships it)"
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

# swaync used to be the notification daemon. Quickshell is the notification
# server itself now (quickshell/NotificationService.qml), and only one process
# can own org.freedesktop.Notifications -- so on a machine upgrading from the
# swaync layout, dropping swaync's config (ORPHANS) and its autostart line is
# NOT enough. Two things still hand the bus name back to swaync:
#
#   * swaync is still RUNNING, started by the old autostart.lua at login, and
#     still holds the name. The bar reload_session restarts below would come up
#     with a bell module that never receives anything -- which reads as the new
#     module being broken rather than as a leftover daemon.
#   * /usr/share/dbus-1/services/org.erikreider.swaync.service declares
#     `Name=org.freedesktop.Notifications`. Any notify-send issued while the
#     name is unowned -- the gap between login and the bar registering, or the
#     second reload_session spends restarting it -- D-Bus-activates swaync,
#     which then keeps the name for the rest of the session. Masking the user
#     unit that activation is delegated to (SystemdService=swaync.service in
#     both of swaync's .service files) is what closes that window.
#
# Guarded on swaync being installed, so it is a no-op on a new machine, and
# idempotent. The swaync *package* is left alone; this script uninstalls
# nothing.
retire_swaync() {
    if ! command -v swaync >/dev/null 2>&1; then
        return 0
    fi

    info "Retiring swaync (quickshell is the notification daemon now)"
    if pkill -x swaync >/dev/null 2>&1; then
        echo "    stopped the running swaync"
    else
        echo "    swaync was not running"
    fi

    # `|| true`: a TTY install may have no user bus to talk to yet, and a
    # cosmetic step must not abort the deploy under `set -e`.
    if systemctl --user mask swaync.service >/dev/null 2>&1; then
        echo "    masked swaync.service, so D-Bus cannot activate it"
        echo "    undo with: systemctl --user unmask swaync.service"
    else
        echo "    could not mask swaync.service (no user bus?) -- harmless unless"
        echo "    something sends a notification before the bar has started"
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

# System settings that are not a file under ~/.config, so deploy_configs cannot
# do them. All three are idempotent, so they run on every deploy rather than
# behind a "first install?" prompt -- the prompt only ever existed because these
# sat beside the optional installers, and answering it wrong on a real first
# install left a machine subtly unfinished with nothing to say so.
#
# The optional halves are gone with it: Tailscale and PIA are no longer installed
# from here. Both are one pacman/paru line, both need an interactive login this
# script could never do anyway, and both bar modules already hide themselves when
# the tool is absent (see PiaPill/TailscalePill). tailscale_commands.txt and
# pia_install.txt at the repo root are the notes. Global git identity is gone for
# the same reason -- it is a `git config --global` line, not a desktop setting.
apply_system_tweaks() {
    info "Applying system settings"

    # localsend and the file manager's network browsing want mDNS.
    sudo systemctl enable --now avahi-daemon
    echo "    avahi-daemon enabled"

    # What xdg-open hands a terminal request to. `-f` so a re-run is a no-op.
    sudo ln -sf /usr/bin/kitty /usr/bin/xdg-terminal-exec
    echo "    xdg-terminal-exec -> kitty"

    # gnome-text-editor keeps this in gsettings, not in a config file.
    gsettings set org.gnome.TextEditor draw-spaces "['space', 'tab', 'trailing']"
    echo "    gnome-text-editor: show whitespace"
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
# save/restore_lock_wallpaper keeps it across later deploys. Deliberately does
# not go through wallpaper-set.sh, which needs the awww daemon up -- during an
# install it is not.
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

# A deploy is not live until something re-reads it: Hyprland parses its config
# at startup and quickshell parses its QML once. Without this, new keybinds and a
# new bar only appear after a logout -- which reads as the deploy having done
# nothing, and is exactly how a changed SUPER+SPACE gets reported as broken.
#
# Skipped when Hyprland is not running (a fresh machine installing from a TTY),
# where the next login picks everything up anyway.
reload_session() {
    if ! command -v hyprctl >/dev/null 2>&1 || ! hyprctl version >/dev/null 2>&1; then
        info "Not reloading"
        echo "    Hyprland is not running -- the new config applies at next login."
        return 0
    fi

    info "Reloading the session"
    # `|| true` throughout: a cosmetic reload must never abort a finished deploy
    # under `set -e`.
    hyprctl reload >/dev/null 2>&1 || true
    echo "    hyprctl reload"

    # Restart the bar last and unconditionally, so exactly one instance is left
    # no matter what the reload above did with exec-once. It owns the SUPER+
    # SPACE / V / W overlays as well as the bar, and `qs ipc call` finds it by
    # the default config path. setsid so it outlives this script.
    killall quickshell >/dev/null 2>&1 || true
    sleep 1
    setsid quickshell >/dev/null 2>&1 &
    disown
    echo "    quickshell restarted (bar + SUPER+SPACE / V / W overlays)"

    check_notification_owner
}

# The bar is only the notification daemon if it actually got the bus name. When
# something else is holding it the symptom is silent -- a bell module that never
# fills up and popups in the wrong style -- so say so plainly instead. Polls
# rather than sleeping a fixed amount, because registering takes a second or two
# and is usually done well before the timeout.
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

    # Both read from files deploy_configs is about to overwrite, so both run
    # first. Each is a no-op on a machine that has nothing to carry over, which
    # is why neither is behind a "first install?" question -- there is no longer
    # anything this script has to be told about the machine it is running on.
    migrate_audio_icons
    save_lock_wallpaper

    deploy_configs
    remove_orphans
    # After remove_orphans (which deletes ~/.config/swaync) and before
    # reload_session, which restarts the bar and expects to be able to claim
    # org.freedesktop.Notifications.
    retire_swaync
    restore_lock_wallpaper

    fix_permissions
    apply_system_tweaks
    apply_gtk_theme
    get_wallpapers
    # After get_wallpapers, so a first install has the images to point at.
    normalize_hyprlock_wallpaper
    # Last: it restarts the bar, which should come up reading the files every
    # step above has finished writing (the icon theme apply_gtk_theme sets
    # included -- the launcher resolves its app icons through it).
    reload_session
    info "Done."
}

main "$@"
