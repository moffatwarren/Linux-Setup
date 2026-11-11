#!/bin/bash
# Deploy this repo's configs to the live system (and pull live changes back).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Config directories: Hyprland_Setup/<name> -> ~/.config/<name>
CONFIGS=(aquarium btop fastfetch fish gtk-3.0 gtk-4.0 haakonlife hypr kitty nvim quickshell superfile weathr wireplumber)

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
    swappy
)

# CachyOS only: paru, brave-origin-bin and localsend live in the `cachyos` repo
# and are not in Arch's. One unresolvable name fails the whole --noconfirm
# transaction, and under `set -e` that aborts the run before deploy_configs --
# so this list is not portable to vanilla Arch and is not meant to be.
PACMAN_PKGS=(
    kitty hyprland quickshell hyprlock hypridle awww ttf-font-awesome
    ttf-jetbrains-mono-nerd btop fastfetch thunar tumbler slurp cliphist grim nwg-look
    wf-recorder gvfs gvfs-smb samba nvim mpv imv brightnessctl playerctl blueman gnome-text-editor
    swayimg imagemagick thunar-archive-plugin xarchiver unzip net-tools localsend spotify-launcher
    speedtest-cli brave-origin-bin paru tesseract tesseract-data-eng zbar adw-gtk-theme cantarell-fonts
    papirus-icon-theme jq libpulse wireplumber pavucontrol power-profiles-daemon networkmanager
    qt6-imageformats libnotify wl-clipboard curl python xdg-utils pacman-contrib fakeroot sddm avahi
    protonup-qt gamescope gnome-calculator mangohud lib32-mangohud github-cli superfile zoxide cifs-utils
    pciutils nodejs
    # Superwhisper's web installer verifies its download's signature only if
    # minisign is ALREADY installed. Its own dependency list does bring minisign
    # in, but after that check has been skipped -- so without this line every
    # first install is checked by SHA-256 over HTTPS alone (setup_superwhisper).
    minisign
    # The Herdr app is a GPU (Vulkan) program that dlopen()s the loader rather than
    # linking it, so no package depends on it for Herdr's sake (setup_herdr).
    vulkan-icd-loader
    # CachyOS's hardware detection tool. setup_gpu_drivers drives it, and the
    # CachyOS installer already put it here -- listed because this script now
    # depends on it, not because anything deployed does.
    chwd
    # Present on this machine only because the CachyOS desktop profile installed
    # them -- nothing above pulls any of them in, so a no-desktop install would
    # deploy the configs that use them and have them silently do nothing:
    #   upower                       BatteryPill, BatteryWatcher, PowerProfileMenu
    #   pipewire-pulse               pactl in audio-output-toggle.sh (wireplumber
    #                                depends on pipewire, not on a pulse provider)
    #   fish                         `fish` is in CONFIGS; the shell itself was not
    #                                in either list
    #   git, base-devel              paru builds PARU_PKGS with them, and LazyVim
    #                                clones its plugins with git on first launch
    #   xdg-desktop-portal-hyprland  hyprland lists it as an OPTIONAL dep, so it
    #                                does not arrive on its own: no screencast
    #   xdg-desktop-portal-gtk       the portal file chooser gtk-3.0/mocha.css themes
    #   bluez-utils                  bluetoothctl; blueman pulls only bluez itself
    # GPU drivers are deliberately NOT in this list. They follow the hardware, by
    # way of chwd's profiles (setup_gpu_drivers). libva-nvidia-driver, which
    # brave/brave-origin-flags.conf switches on, comes with the NVIDIA profile:
    # listed here, it would come back on every run after a swap to AMD removed it.
    upower pipewire-pulse fish git base-devel xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk bluez-utils
)

PARU_PKGS=(
    pokemon-colorscripts-git rustdesk-bin teams-for-linux vscodium-bin
    papirus-folders-catppuccin-git
)

# Superwhisper's dictation keys, as `superwhisper shortcuts set <name> <key>`
# takes them ("none" disables one). Only SEEDED, on a machine whose Superwhisper
# has never had working shortcuts -- after that its own settings window owns
# them and a deploy leaves them alone (setup_superwhisper). hold goes first:
# Superwhisper refuses a change that would leave no recording shortcut at all.
# KeybindsHelp.qml and README.md name the hold key; change them together.
SUPERWHISPER_SHORTCUTS=(hold=RightControl toggle=none mouse=none cancel=Escape)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

usage() {
    cat <<EOF
Usage: install.sh [OPTION]

  (no option)   Install packages and deploy this repo's configs to the live
                system. Handles both first-time install and routine updates,
                and asks no questions (sudo aside).
  --pull        Copy the LIVE configs back into this repo so changes made on
                the machine can be reviewed and committed. Does not commit.
  --gpu-check   Show which GPUs are installed and what a full run would change
                about their drivers. Changes nothing and needs no sudo.
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

# config.fileManager used to be what SUPER+E ran. It is gone -- SUPER+E now
# opens whatever the SUPER+D menu has as the default file explorer -- and a
# retired value needs a migration, not just a deleted line: deploy_configs is
# about to overwrite config.lua, and with it the only record of which file
# explorer this machine used. So it is read out of the LIVE copy first, and
# ensure_file_manager_default hands it on after the deploy. Self-limiting: once
# the new config.lua is deployed there is no such line left to read.
LEGACY_FILE_MANAGER=""

save_file_manager() {
    local conf="$HOME/.config/hypr/modules/config.lua"
    [ -f "$conf" ] || return 0
    LEGACY_FILE_MANAGER="$(sed -nE \
        '/^[[:space:]]*config\.fileManager[[:space:]]*=/{s/^[^=]*=[[:space:]]*["'"'"']([^"'"'"']*)["'"'"'].*/\1/;p;q}' \
        "$conf" || true)"
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
install_packages() {
    info "Installing packages"
    local pkgs
    mapfile -t pkgs < <(to_install "${PACMAN_PKGS[@]}")
    if [ "${#pkgs[@]}" -gt 0 ]; then
        sudo pacman -S --noconfirm --needed "${pkgs[@]}"
    fi
    mapfile -t pkgs < <(to_install "${PARU_PKGS[@]}")
    if [ "${#pkgs[@]}" -gt 0 ]; then
        paru -S --noconfirm --skipreview --needed "${pkgs[@]}"
    fi

    check_nerd_font
}

# Print the names in "$@" that should go to `-S`, dropping any that an installed
# package of a DIFFERENT name already provides. `--needed` only skips a name whose
# own package is installed, so `nodejs` beside nodejs-lts-iron (which provides
# nodejs and conflicts with it) is not skipped: pacman offers to swap them, and
# --noconfirm answers that [y/N] with N, failing the whole transaction. A name
# installed under its own name is kept, so --needed behaves exactly as before.
# Note `pacman -Q <name>` cannot make this test: it resolves provides too.
to_install() {
    local -A installed=() unsatisfied=()
    local p
    while read -r p; do installed[$p]=1; done < <(pacman -Qq)
    while read -r p; do unsatisfied[$p]=1; done < <(pacman -T "$@" || true)
    for p in "$@"; do
        if [ -n "${installed[$p]:-}" ] || [ -n "${unsatisfied[$p]:-}" ]; then
            printf '%s\n' "$p"
        else
            printf '%s is provided by %s -- skipping\n' "$p" \
                "$(pacman -Qq "$p" 2>/dev/null)" >&2
        fi
    done
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

# ---------------------------------------------------------------------------
# GPU drivers
# ---------------------------------------------------------------------------
# Which driver a GPU needs is chwd's call, not a package list here. chwd is
# CachyOS's hardware detection tool, and its profiles already know every vendor
# and generation (NVIDIA open / 580xx / 470xx / nouveau and their laptop
# ".prime" variants, AMD, Intel) plus the per-kernel module packages and the
# initramfs settings each one needs. What this adds is the hardware CHANGING:
#   - a display device no installed profile covers gets chwd's best profile;
#   - on a desktop, an installed profile no device asks for any more is removed.
# With the same hardware as last time it changes nothing, and that is the point.
# chwd installs with `pacman -S --needed`, which upgrades an out-of-date package,
# and under --noconfirm even one held in IgnorePkg. Re-running it on every deploy
# would push the NVIDIA driver straight past the hold that keeps 620 off this
# machine. See "GPU drivers follow the hardware" in CLAUDE.md.
CHWD_DB=/var/lib/chwd/db/pci/graphic_drivers/profiles.toml
CHWD_LOCAL=/var/lib/chwd/local/pci/graphic_drivers/profiles.toml
CHWD_LOCAL_DIR=/var/lib/chwd/local
PACMAN_CONF=/etc/pacman.conf
GPU_CHASSIS_FILE="${GPU_CHASSIS_FILE:-/sys/class/dmi/id/chassis_type}"

# The NVIDIA 620 hold from CLAUDE.md. It is never ADDED from here: on a fresh
# machine that would pin the broken driver in place rather than keep it out. But
# once no NVIDIA hardware or driver is left it pins nothing but the kernel, so it
# is taken back out of /etc/pacman.conf.
NVIDIA_HOLD=(
    nvidia-utils lib32-nvidia-utils opencl-nvidia lib32-opencl-nvidia nvidia-settings
    libxnvctrl linux-cachyos linux-cachyos-headers linux-cachyos-nvidia-open
    linux-cachyos-lts linux-cachyos-lts-headers linux-cachyos-lts-nvidia-open
)

gpu_vendor() {
    case "$1" in
        10de) echo NVIDIA ;;
        1002) echo AMD ;;
        8086) echo Intel ;;
        *)    echo "$1" ;;
    esac
}

# Every graphics profile name chwd knows: shipped, or installed by an older chwd
# whose name the shipped database may since have dropped.
chwd_graphics_names() {
    cat "$CHWD_DB" "$CHWD_LOCAL" 2>/dev/null |
        sed -nE 's/^\[([A-Za-z0-9._-]+)\][[:space:]]*$/\1/p' | LC_ALL=C sort -u
}

# chwd prints tables ("│ name ┆ priority │"), not data, so both listings are
# parsed from those rows. ANSI colour is stripped in case a later chwd colours
# its output even when it is not writing to a terminal.
#
# gpu_offers: "bdf class vendor profile priority" for each graphics profile chwd
# offers a display device -- PCI class 0300 (VGA), 0302 (3D) or 0380 (other).
gpu_offers() {
    chwd --list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' |
        awk -v names="$(chwd_graphics_names | tr '\n' ' ')" '
            BEGIN { n = split(names, a, " "); for (i = 1; i <= n; i++) g[a[i]] = 1 }
            /^> / {
                dev = ""
                if (match($0, /\([0-9a-f]+:[0-9a-f]+:[0-9a-f]+\)/)) {
                    split(substr($0, RSTART + 1, RLENGTH - 2), id, ":")
                    if (id[1] ~ /^03(00|02|80)$/) { dev = $2; cls = id[1]; ven = id[2] }
                }
                next
            }
            dev != "" && index($0, "┆") {
                row = $0; gsub("│", "", row); sub("┆", " ", row)
                if (split(row, f, " ") == 2 && f[2] ~ /^[0-9]+$/ && (f[1] in g))
                    print dev, cls, ven, f[1], f[2]
            }'
}

# gpu_installed: the installed graphics profiles, one per line.
gpu_installed() {
    chwd --list-installed 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' |
        awk -v names="$(chwd_graphics_names | tr '\n' ' ')" '
            BEGIN { n = split(names, a, " "); for (i = 1; i <= n; i++) g[a[i]] = 1 }
            index($0, "┆") {
                row = $0; gsub("│", "", row); sub("┆", " ", row)
                if (split(row, f, " ") == 2 && f[2] ~ /^[0-9]+$/ && (f[1] in g)) print f[1]
            }'
}

# A one-line string field of [profile] in a chwd profiles file. Headers are
# matched whole, so a hook line such as "[ -z ... ]" is never taken for one.
profile_field() {   # file profile key
    awk -v sec="[$2]" -v key="$3" -v q="'" '
        /^\[[A-Za-z0-9._-]+\][[:space:]]*$/ { s = ($1 == sec); next }
        s && $1 == key && $2 == "=" {
            v = $0; sub(/^[^=]*=[[:space:]]*/, "", v)
            gsub("^[\"" q "]|[\"" q "][[:space:]]*$", "", v)
            print v; exit
        }' "$1" 2>/dev/null
}

# A multi-line """ field of [profile]: a hook, or conditional_packages.
profile_block() {   # file profile key
    awk -v sec="[$2]" -v key="$3" '
        !c && /^\[[A-Za-z0-9._-]+\][[:space:]]*$/ { s = ($1 == sec); next }
        s && !c && $1 == key && $2 == "=" && $3 == "\"\"\"" { c = 1; next }
        c && /^[[:space:]]*"""[[:space:]]*$/ { exit }
        c' "$1" 2>/dev/null
}

is_nvidia_profile() {   # profile
    [ "$1" = fallback ] && return 1   # mesa + vesa: names every vendor, belongs to none
    case "$1" in nvidia*|nouveau*) return 0 ;; esac
    case " $(profile_field "$CHWD_LOCAL" "$1" vendor_ids) " in *" 10de "*) return 0 ;; esac
    return 1
}

# What `chwd -r <profile>` hands to pacman, worked out the way chwd's own
# remove() does it: the profile's packages plus whatever its conditional_packages
# snippet prints (for NVIDIA, one kernel module package per installed CachyOS
# kernel), installed under that exact name, minus mesa and lib32-mesa, which chwd
# never removes. Read from the INSTALLED copy of the profile, the one chwd
# removes by, not the shipped one, whose package list may have changed since.
profile_packages() {   # profile
    {
        profile_field "$CHWD_LOCAL" "$1" packages | tr -s ' ' '\n'
        profile_block "$CHWD_LOCAL" "$1" conditional_packages | bash 2>/dev/null | tr -s ' ' '\n'
    } | { grep -vxE 'mesa|lib32-mesa|' || true; } | LC_ALL=C sort -u |
        LC_ALL=C comm -12 - <(pacman -Qq | LC_ALL=C sort)
}

# Of the packages given, the ones pacman itself would refuse to remove, because
# something else still needs them. `pacman -Rp` is a dry run, needs no root, and
# resolves provides, which is what keeps nvidia-utils OUT of this set once mesa
# is there: opengl-driver, the thing hyprland and aquamarine ask for, comes from
# mesa too. A package that is only needed by one of the refused ones shows up on
# the next round, hence the loop. Exits 1 if pacman fails for any other reason.
removal_keepers() {   # packages...
    local -a cand=("$@") keep=() new=()
    local out ok=""
    for _ in 1 2 3 4 5 6 7 8; do
        if [ "${#cand[@]}" -eq 0 ] || out="$(LC_ALL=C pacman -Rp "${cand[@]}" 2>&1)"; then
            ok=1
            break
        fi
        mapfile -t new < <(sed -nE 's/^:: removing ([^ ]+) breaks dependency .*/\1/p' <<<"$out" | LC_ALL=C sort -u)
        [ "${#new[@]}" -gt 0 ] || return 1
        keep+=("${new[@]}")
        mapfile -t cand < <(printf '%s\n' "${cand[@]}" | { grep -vxF -f <(printf '%s\n' "${keep[@]}") || true; })
    done
    [ -n "$ok" ] || return 1
    printf '%s\n' "${keep[@]}" | sed '/^$/d' | LC_ALL=C sort -u
}

# Remove driver profiles whose hardware is gone. chwd removes with `pacman -Rdd`,
# which skips the dependency check, and the NVIDIA profile lists packages that
# are not NVIDIA's: vulkan-icd-loader is needed by gtk4, ffmpeg, mpv and steam,
# and lib32-vulkan-icd-loader by steam. So pacman is asked first what it would
# refuse to remove, chwd removes the profile (its own hooks put the initramfs
# settings back), and exactly those packages are reinstalled afterwards, together
# with anything chwd took that PACMAN_PKGS or a still-installed profile lists.
gpu_remove() {   # profiles...
    local p out before explicit after
    local -a pkgs=() keep=() removed=() wanted=() back=() back_explicit=() back_deps=()

    mapfile -t pkgs < <(for p in "$@"; do profile_packages "$p"; done | LC_ALL=C sort -u)
    if ! out="$(removal_keepers "${pkgs[@]}")"; then
        echo "    WARNING: pacman could not say what removing $* would break,"
        echo "             so it is left installed."
        return 1
    fi
    mapfile -t keep < <(sed '/^$/d' <<<"$out")

    before="$(pacman -Qq | LC_ALL=C sort)"
    explicit="$(pacman -Qqe | LC_ALL=C sort)"
    for p in "$@"; do
        if sudo chwd -r "$p"; then
            echo "    removed $p"
        else
            echo "    WARNING: chwd could not remove $p"
        fi
    done
    after="$(pacman -Qq | LC_ALL=C sort)"

    mapfile -t removed < <(LC_ALL=C comm -23 <(printf '%s\n' "$before") <(printf '%s\n' "$after"))
    [ "${#removed[@]}" -gt 0 ] || return 0
    mapfile -t wanted < <({
        printf '%s\n' "${keep[@]}" "${PACMAN_PKGS[@]}"
        while read -r p; do
            profile_field "$CHWD_LOCAL" "$p" packages | tr -s ' ' '\n'
        done < <(gpu_installed)
    } | sed '/^$/d' | LC_ALL=C sort -u)
    mapfile -t back < <(LC_ALL=C comm -12 <(printf '%s\n' "${removed[@]}") <(printf '%s\n' "${wanted[@]}"))
    [ "${#back[@]}" -gt 0 ] || return 0

    for p in "${back[@]}"; do
        if grep -qxF "$p" <<<"$explicit"; then back_explicit+=("$p"); else back_deps+=("$p"); fi
    done
    echo "    reinstalling what other software still needs: ${back[*]}"
    if { [ "${#back_explicit[@]}" -eq 0 ] || sudo pacman -S --noconfirm --needed "${back_explicit[@]}"; } &&
       { [ "${#back_deps[@]}" -eq 0 ] || sudo pacman -S --noconfirm --needed --asdeps "${back_deps[@]}"; }; then
        return 0
    fi
    echo "    WARNING: could not reinstall them. Do it by hand before rebooting:"
    echo "               sudo pacman -S --needed ${back[*]}"
}

# Files chwd generated under /etc that no installed profile accounts for. chwd's
# own removal deletes a profile's files, but only the ones that profile knew
# about when it was installed. A file is a candidate only if it carries chwd's
# "automatically generated" line, and it is stale only when no installed chwd
# profile, of any kind, mentions it by name.
gpu_stale_files() {
    local f
    for f in /etc/mkinitcpio.conf.d/10-chwd*.conf /etc/modprobe.d/chwd-*.conf; do
        [ -f "$f" ] || continue
        grep -q "automatically generated by chwd" "$f" 2>/dev/null || continue
        grep -rqF "${f##*/}" "$CHWD_LOCAL_DIR" 2>/dev/null || printf '%s\n' "$f"
    done
}

rebuild_initramfs() {
    if command -v limine-mkinitcpio >/dev/null 2>&1; then
        sudo limine-mkinitcpio
    else
        sudo mkinitcpio -P
    fi
}

# /etc/pacman.conf with the NVIDIA hold's names taken out of every IgnorePkg
# line, on stdout. Other held names stay. A line left empty goes back to the
# commented-out "#IgnorePkg   =" pacman.conf ships with. Exits 1 when no line
# held any of them, so there is nothing to write.
strip_nvidia_hold() {   # conf
    awk -v drop="${NVIDIA_HOLD[*]}" '
        BEGIN { n = split(drop, a, " "); for (i = 1; i <= n; i++) d[a[i]] = 1 }
        /^[[:space:]]*IgnorePkg[[:space:]]*=/ {
            v = $0; sub(/^[^=]*=/, "", v)
            m = split(v, p, " "); out = ""; hit = 0
            for (i = 1; i <= m; i++) {
                if (p[i] in d) { hit = 1; continue }
                out = out (out == "" ? "" : " ") p[i]
            }
            if (hit) {
                changed = 1
                print (out == "" ? "#IgnorePkg   =" : "IgnorePkg = " out)
                next
            }
        }
        { print }
        END { exit !changed }' "$1"
}

release_nvidia_hold() {
    local conf="$PACMAN_CONF" tmp
    tmp="$(mktemp)"
    if ! strip_nvidia_hold "$conf" >"$tmp"; then
        rm -f "$tmp"
        return 0
    fi
    # Only written if pacman can still read the result and finds none of the names.
    if pacman-conf --config "$tmp" >/dev/null 2>&1 &&
       ! pacman-conf --config "$tmp" IgnorePkg | grep -qxF -f <(printf '%s\n' "${NVIDIA_HOLD[@]}") &&
       sudo cp -p "$conf" "$conf.before-gpu-change" &&
       sudo install -m 644 -o root -g root "$tmp" "$conf"; then
        echo "    released the NVIDIA hold in $conf (previous copy: $conf.before-gpu-change)"
        echo "    run 'paru' to update the kernel and the rest of what it held back"
    else
        echo "    WARNING: could not release the NVIDIA hold. Take these out of IgnorePkg"
        echo "             in $conf by hand: ${NVIDIA_HOLD[*]}"
    fi
    rm -f "$tmp"
}

# A laptop never has a profile removed. A dGPU that is switched off -- by
# supergfxctl, envycontrol or a firmware MUX -- can drop off the PCI bus entirely
# and look exactly like a card that has been taken out. Chassis types from the
# SMBIOS spec: portable, laptop, notebook, hand held, sub notebook, tablet,
# convertible, detachable.
gpu_portable() {
    case "$(cat "$GPU_CHASSIS_FILE" 2>/dev/null)" in
        8|9|10|11|14|30|31|32) return 0 ;;
    esac
    return 1
}

setup_gpu_drivers() {   # [--check]
    local check=""
    [ "${1:-}" = --check ] && check=1
    info "GPU drivers"

    if ! command -v chwd >/dev/null 2>&1 || [ ! -f "$CHWD_DB" ]; then
        echo "    skip (chwd, CachyOS's hardware detection tool, is not installed)"
        return 0
    fi

    local -a offers=() installed=() devs=() add=() stale=() files=()
    mapfile -t offers < <(gpu_offers)
    mapfile -t installed < <(gpu_installed)
    if [ "${#offers[@]}" -eq 0 ]; then
        echo "    WARNING: chwd offers no driver for any display device, so nothing is"
        echo "             changed. 'chwd --list' shows what it sees."
        return 0
    fi

    local line dev cls ven prof prio p nv_hw="" nv_kept=""
    local -A is_installed=() offered=() best=() best_prio=() covered=() using=() vendor=()
    for p in "${installed[@]}"; do is_installed[$p]=1; done
    for line in "${offers[@]}"; do
        read -r dev cls ven prof prio <<<"$line"
        offered[$prof]=1
        vendor[$dev]="$ven"
        [ "$ven" = 10de ] && nv_hw=1
        if [ -z "${best_prio[$dev]:-}" ] || [ "$prio" -gt "${best_prio[$dev]}" ]; then
            best[$dev]="$prof"
            best_prio[$dev]="$prio"
        fi
        # Any installed profile that is offered for the device covers it, not
        # only the best one. So a working driver is never swapped for another
        # just because CachyOS ships a new favourite.
        if [ -n "${is_installed[$prof]:-}" ] && [ "$prof" != fallback ]; then
            covered[$dev]=1
            using[$dev]="$prof"
        fi
    done

    mapfile -t devs < <(printf '%s\n' "${!best[@]}" | LC_ALL=C sort)
    for dev in "${devs[@]}"; do
        # fallback (mesa + vesa) covers a device only when nothing better is offered
        if [ -z "${covered[$dev]:-}" ] && [ "${best[$dev]}" = fallback ] && [ -n "${is_installed[fallback]:-}" ]; then
            covered[$dev]=1
            using[$dev]=fallback
        fi
        if [ -n "${covered[$dev]:-}" ]; then
            printf '    %s  %-6s  %s\n' "$dev" "$(gpu_vendor "${vendor[$dev]}")" "${using[$dev]}"
        else
            printf '    %s  %-6s  needs %s, which is not installed\n' "$dev" "$(gpu_vendor "${vendor[$dev]}")" "${best[$dev]}"
            case " ${add[*]} " in *" ${best[$dev]} "*) ;; *) add+=("${best[$dev]}") ;; esac
        fi
    done
    for p in "${installed[@]}"; do
        [ "$p" = fallback ] || [ -n "${offered[$p]:-}" ] || stale+=("$p")
    done
    for p in "${stale[@]}"; do
        echo "    $p is installed, but no device needs it any more"
    done

    if [ "${#stale[@]}" -gt 0 ] && gpu_portable; then
        echo "    Not removing ${stale[*]}: on a laptop a switched-off GPU can drop off the"
        echo "    PCI bus and look removed. If the hardware really is gone:"
        for p in "${stale[@]}"; do echo "      sudo chwd -r $p"; done
        stale=()
    fi
    for p in "${installed[@]}"; do
        if is_nvidia_profile "$p" && [[ " ${stale[*]} " != *" $p "* ]]; then nv_kept=1; fi
    done
    [ "${#add[@]}" -gt 0 ] || [ "${#stale[@]}" -gt 0 ] || echo "    drivers match the hardware"

    if [ -n "$check" ]; then
        [ "${#add[@]}" -eq 0 ] || echo "    would install: ${add[*]}"
        for p in "${stale[@]}"; do
            echo "    would remove $p: $(profile_packages "$p" | tr '\n' ' ')"
        done
        [ "${#stale[@]}" -eq 0 ] ||
            echo "    (anything on that list other software still needs is reinstalled straight after)"
        mapfile -t files < <(gpu_stale_files)
        [ "${#files[@]}" -eq 0 ] || echo "    would delete ${files[*]} and rebuild the initramfs"
        if [ -z "$nv_hw" ] && [ -z "$nv_kept" ] && strip_nvidia_hold "$PACMAN_CONF" >/dev/null; then
            echo "    would release the NVIDIA hold in $PACMAN_CONF"
        fi
        return 0
    fi

    local changed="" failed=""
    for p in "${add[@]}"; do
        if sudo chwd -i "$p"; then
            echo "    installed $p"
            changed=1
        else
            echo "    WARNING: chwd could not install $p. Update the system ('paru') and"
            echo "             run this again."
            failed=1
        fi
    done
    if [ "${#stale[@]}" -gt 0 ]; then
        if [ -n "$failed" ]; then
            echo "    not removing ${stale[*]} until the new driver is installed"
        elif gpu_remove "${stale[@]}"; then
            changed=1
        fi
    fi

    mapfile -t files < <(gpu_stale_files)
    if [ "${#files[@]}" -gt 0 ] && sudo rm -f "${files[@]}"; then
        echo "    deleted ${files[*]}"
        if rebuild_initramfs; then
            echo "    initramfs rebuilt"
        else
            echo "    WARNING: the initramfs did not rebuild. Run 'sudo limine-mkinitcpio' before rebooting."
        fi
        changed=1
    fi

    # Re-read: NVIDIA counts as gone only once neither a card nor a driver is left.
    nv_kept=""
    while read -r p; do is_nvidia_profile "$p" && nv_kept=1; done < <(gpu_installed)
    [ -n "$nv_hw" ] || [ -n "$nv_kept" ] || release_nvidia_hold

    [ -z "$changed" ] || echo "    reboot to start on the new driver"
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
    # udev rules, file by file: rules.d is shared with every package's rules.
    # Re-triggered so a rule applies now, not at the next boot -- the RAPL one
    # is what gives the power-profile menu its CPU power row.
    sudo mkdir -p /etc/udev/rules.d
    sudo \cp -f "$SCRIPT_DIR"/udev/*.rules /etc/udev/rules.d
    sudo udevadm control --reload || true
    sudo udevadm trigger --action=add --subsystem-match=powercap || true
    echo "    udev rules (system)"
    # Desktop entries for apps whose package ships none (superfile). Copied file
    # by file: the directory is shared with every other app's entries and with
    # mimeinfo.cache, so it is never deployed or pulled as a whole.
    mkdir -p "$HOME/.local/share/applications"
    \cp -f "$SCRIPT_DIR"/applications/*.desktop "$HOME/.local/share/applications"
    echo "    applications (~/.local/share)"
    # A bare file in ~/.config, which CONFIGS cannot express: it copies directories.
    \cp -f "$SCRIPT_DIR/brave/brave-origin-flags.conf" "$HOME/.config"
    echo "    brave-origin-flags.conf"
    # Herdr's settings and the two Catppuccin themes they name, plus Pip (a mod)
    # and main-pip (the copy of Herdr's main layout that gives Pip its spot), file
    # by file: ~/.config/herdr-app is mostly Herdr's own (docs, icons, mods, state,
    # a socket), rewritten on every start, so it is never deployed or pulled whole.
    # Herdr also writes gpui-kit.d.ts and jsconfig.json into every mod folder,
    # which is why Pip's two files are named rather than globbed.
    local herdr="$HOME/.config/herdr-app"
    mkdir -p "$herdr/themes" "$herdr/mods/pip" "$herdr/layouts"
    \cp -f "$SCRIPT_DIR/herdr-app/settings.json" "$herdr"
    \cp -f "$SCRIPT_DIR"/herdr-app/themes/*.json "$herdr/themes"
    \cp -f "$SCRIPT_DIR/herdr-app/mods/pip/main.js" "$SCRIPT_DIR/herdr-app/mods/pip/mod.json" "$herdr/mods/pip"
    \cp -f "$SCRIPT_DIR/herdr-app/layouts/main-pip.json" "$herdr/layouts"
    # Where Herdr has never run there is no shared.json yet, and its first start
    # would show the stock `main`, without Pip. Seeding the one key makes it start
    # on main-pip; Herdr keeps the key and adds its own (verified on a fresh
    # HERDR_APP_HOME: seeded -> main-pip with Pip; unseeded -> main). Once Herdr
    # has written the file it is Herdr's and is never touched here --
    # use_herdr_pip_layout handles a machine that already has one.
    if [ ! -e "$herdr/shared.json" ]; then
        printf '{"layout":"main-pip"}\n' > "$herdr/shared.json"
    fi
    echo "    herdr-app (settings.json + themes + Pip and its layout)"
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

# An earlier hypr/scripts/default-apps.sh set the text editor for 265 MIME
# types swept out of /usr/share/mime/globs2 by regex -- application/postscript
# among them. The current script ships a curated list instead, but dropping the
# sweep only stops it writing them: "deleting something from the repo does not
# delete it from the machine". --prune is what removes the ones already in
# ~/.config/mimeapps.list, and it is self-limiting -- after one run there is
# nothing left to match. It runs after deploy_configs, since it is the freshly
# deployed script that knows which associations the current list keeps.
prune_mime_sweep() {
    local script="$HOME/.config/hypr/scripts/default-apps.sh"
    [ -x "$script" ] || return 0

    local out
    out=$("$script" --prune 2>/dev/null) || return 0
    case "$out" in
        "removed 0 "*) ;;
        *) info "Pruning stale MIME associations"; echo "    $out" ;;
    esac
}

# Give folders an explicit default when they have none worth keeping. Two
# cases, both one-shot: carrying a legacy config.fileManager across (above),
# and a machine where GIO resolves folders to something that is not a file
# explorer at all -- VSCodium, on this one, because an IDE declares it can open
# a directory. It never overrides an explicit choice, and never overrides GIO
# when GIO already names a real file explorer. See --ensure-filemanager in
# default-apps.sh. Runs after fix_permissions, since it asks the deployed copy.
ensure_file_manager_default() {
    local script="$HOME/.config/hypr/scripts/default-apps.sh"
    [ -f "$script" ] || return 0

    local out
    out=$(bash "$script" --ensure-filemanager "$LEGACY_FILE_MANAGER" 2>/dev/null) || return 0
    if [ -n "$out" ]; then
        info "Setting the default file explorer"
        echo "    $out"
        [ -n "$LEGACY_FILE_MANAGER" ] && echo "    (carried over from config.fileManager = \"$LEGACY_FILE_MANAGER\")"
    fi
    return 0
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

# Units the session needs that deploy_configs cannot reach. `enable` is a no-op
# on an already-enabled unit, so like apply_system_tweaks these run every time
# rather than behind a "first install?" question.
#
# This is the step that decides whether a fresh machine can log in at all. sddm
# is in PACMAN_PKGS, deploy_configs puts the theme in /usr/share/sddm/themes and
# names it in /etc/sddm.conf.d -- and before this, nothing ever started it, so a
# no-desktop install ended at a TTY holding a fully configured session it had no
# way to reach. Same shape for the other two: NetworkManager is what WifiMenu and
# NetworkPill read through, and bluetoothd is what BluetoothPill talks to; both
# were installed and neither was running.
#
# Every branch is guarded rather than left to `set -e`: a service that will not
# enable is worth a warning, not a deploy that stops after the configs are
# already copied. Same rule as papirus-folders in apply_gtk_theme.
enable_services() {
    info "Enabling services"

    # NOT --now. sddm takes a VT, and starting it from inside the very session
    # it is meant to launch pulls the display out from under Hyprland. It is a
    # boot-time unit, so the next boot is when it should first run.
    # The -L test is what settles "is there a display manager", NOT readlink's
    # exit status: `readlink -f` canonicalizes a path whose last component does
    # not exist and still exits 0, so on the machine this whole function is for
    # -- a fresh install with no DM -- it hands back the query path itself and
    # dm becomes "display-manager.service", which reads as some other DM being
    # in charge and skips the one enable that matters.
    local dm=""
    if [ -L /etc/systemd/system/display-manager.service ]; then
        dm="$(basename "$(readlink -f /etc/systemd/system/display-manager.service)")"
    fi
    case "$dm" in
        sddm.service)
            echo "    sddm already enabled" ;;
        "")
            if sudo systemctl enable sddm >/dev/null 2>&1; then
                echo "    sddm enabled (takes effect at the next boot)"
            else
                echo "    WARNING: could not enable sddm. Until it is, log in from a TTY"
                echo "             by running 'Hyprland', or enable it by hand:"
                echo "               sudo systemctl enable sddm"
            fi ;;
        *)
            echo "    skip sddm (${dm%.service} is the display manager on this machine)" ;;
    esac

    # Enabling NetworkManager beside a running systemd-networkd makes two things
    # fight over the same interfaces, so that machine keeps what it has.
    if systemctl is-active NetworkManager >/dev/null 2>&1; then
        sudo systemctl enable NetworkManager >/dev/null 2>&1 || true
        echo "    NetworkManager already running"
    elif systemctl is-active systemd-networkd >/dev/null 2>&1; then
        echo "    skip NetworkManager (systemd-networkd is managing the network)"
    elif sudo systemctl enable --now NetworkManager >/dev/null 2>&1; then
        echo "    NetworkManager enabled"
    else
        echo "    WARNING: could not enable NetworkManager -- the network module"
        echo "             and nmcli will have nothing to report."
    fi

    # Not guarded on an adapter being present: bluetoothd with no hardware just
    # idles, and guarding would mean a dongle plugged in later found nothing
    # listening. BluetoothPill hides itself when there is no adapter anyway.
    if ! systemctl cat bluetooth.service >/dev/null 2>&1; then
        echo "    skip bluetooth (no bluetooth.service on this machine)"
    elif systemctl is-active bluetooth >/dev/null 2>&1; then
        sudo systemctl enable bluetooth >/dev/null 2>&1 || true
        echo "    bluetooth already running"
    elif sudo systemctl enable --now bluetooth >/dev/null 2>&1; then
        echo "    bluetooth enabled"
    else
        echo "    WARNING: could not enable bluetooth -- BluetoothMenu will stay empty."
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

# Seed ~/Pictures/wallpapers with the repo's starter wallpaper(s) so a fresh
# machine has at least one for the picker, wallpaper-random.sh and hyprlock.
# The full collection lives in its own repo; this only copies files that are
# not already there (-n), so nothing in the live folder is ever overwritten.
get_wallpapers() {
    local dest="$HOME/Pictures/wallpapers" f copied=0
    [ -d "$REPO_ROOT/wallpapers" ] || return 0
    mkdir -p "$dest"
    for f in "$REPO_ROOT/wallpapers"/*; do
        [ -f "$f" ] || continue
        [ -e "$dest/${f##*/}" ] && continue
        [ "$copied" -eq 1 ] || info "Seeding wallpapers"
        \cp -n "$f" "$dest/"
        echo "    ${f##*/}"
        copied=1
    done
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

# Superwhisper (dictation). Not a package: its own installer puts it under
# ~/.local/share/superwhisper, runs it as superwhisper.service and installs a
# timer that updates it every 6 h -- so this installs it only where it is
# missing, and never re-runs the installer to update it.
#
# Runs after deploy_configs on purpose. The installer ends with `superwhisper
# shortcuts apply`, which refuses unless ~/.config/hypr/bindings.lua exists
# (see that file), and leaves the machine with no binds at all if it does.
#
# The keys are seeded from SUPERWHISPER_SHORTCUTS only while
# ~/.config/superwhisper/shortcuts.lua -- the binds Superwhisper generates --
# does not exist, checked BEFORE the installer runs, since a successful install
# writes one with Superwhisper's own defaults. Once it exists the settings
# window owns the keys: re-setting them every deploy would silently undo a key
# changed there. Setting a key makes Superwhisper reload Hyprland, so it needs a
# running session; from a TTY this step installs and the next run seeds.
#
# Every step is guarded: a dictation app that fails to install is worth a
# warning, not a deploy stopped before reload_session.
setup_superwhisper() {
    local installer_url="https://tux.superwhisper.com/install.sh"
    local app="${XDG_DATA_HOME:-$HOME/.local/share}/superwhisper/app/current"
    local generated="${XDG_CONFIG_HOME:-$HOME/.config}/superwhisper/shortcuts.lua"
    local sw="$HOME/.local/bin/superwhisper"
    local seed=0 installer current pair name key want have

    info "Superwhisper (dictation)"
    [ -f "$generated" ] || seed=1

    if [ -x "$app/run.sh" ] && [ -x "$sw" ]; then
        echo "    installed ($(cat "$app/VERSION" 2>/dev/null || echo "unknown version")); it updates itself"
    else
        # Downloaded first rather than piped: `sh` then runs a complete file,
        # and the installer finds the terminal itself for its sudo prompt.
        installer="$(mktemp)"
        if curl --proto '=https' --tlsv1.2 -fsSL "$installer_url" -o "$installer" \
            && sh "$installer"; then
            echo "    installed"
        else
            echo "    WARNING: Superwhisper did not install. Rerun install.sh, or by hand:"
            echo "               curl -fsSL $installer_url | sh"
        fi
        rm -f "$installer"
        [ -x "$sw" ] || return 0
    fi

    if [ "$seed" -eq 0 ]; then
        echo "    shortcuts: left as Superwhisper's settings have them"
        return 0
    fi
    if ! hyprctl version >/dev/null 2>&1; then
        echo "    shortcuts not set: Hyprland is not running. Rerun install.sh from"
        echo "    the session to set them (${SUPERWHISPER_SHORTCUTS[*]})."
        return 0
    fi

    current="$("$sw" shortcuts show 2>/dev/null)" || current='{}'
    for pair in "${SUPERWHISPER_SHORTCUTS[@]}"; do
        name="${pair%%=*}" key="${pair#*=}"
        if [ "$key" = none ]; then want=""; else want="$key"; fi
        have="$(jq -r --arg n "$name" '.shortcuts[$n] // ""' <<<"$current" 2>/dev/null)" || have="?"
        [ "$have" = "$want" ] && continue
        if "$sw" shortcuts set "$name" "$key" >/dev/null 2>&1; then
            echo "    $name -> $key"
        else
            echo "    WARNING: Superwhisper refused $name = $key -- another bind may"
            echo "             hold it. Pick one in Superwhisper's settings."
        fi
    done
    # Every key already matched, so nothing above has written the binds yet.
    if [ ! -f "$generated" ]; then
        if "$sw" shortcuts apply >/dev/null 2>&1; then
            echo "    shortcuts: binds written (${SUPERWHISPER_SHORTCUTS[*]})"
        else
            echo "    WARNING: Superwhisper could not write its binds. Run"
            echo "             'superwhisper shortcuts apply' to see why."
        fi
    fi
}

# Herdr (terminals and coding agents) is not a package either: its installer puts
# the app in ~/.local/share/herdr-app with `herdr-app` in ~/.local/bin and a
# launcher entry, and installs herdr-core (`hc`, which runs the terminals) beside
# it when there is none. From then on the app updates itself and the core, so the
# installer runs only where the app is missing. Its look -- the Catppuccin themes
# and the settings.json that picks them -- is deployed by deploy_configs whether
# or not the app is here yet: Herdr reads it on its first start. No sudo, and
# never fatal: a failed download is a warning, not a stopped deploy.
setup_herdr() {
    local installer_url="https://releases.herdr.dev/app/install.sh"
    local app="${XDG_DATA_HOME:-$HOME/.local/share}/herdr-app/herdr-app"
    local installer

    info "Herdr (terminals and agents)"
    if [ -x "$app" ] && [ -e "$HOME/.local/bin/herdr-app" ]; then
        echo "    installed; it updates itself"
        return 0
    fi
    installer="$(mktemp)"
    if curl --proto '=https' --tlsv1.2 -fsSL "$installer_url" -o "$installer" \
        && sh "$installer"; then
        echo "    installed"
    else
        echo "    WARNING: Herdr did not install. Rerun install.sh, or by hand:"
        echo "               curl -fsSL $installer_url | sh"
    fi
    rm -f "$installer"
}

# Pip's spot is a block in main-pip, a copy of Herdr's own main layout: shipped
# layouts are read-only and replaced on every start, so the copy is the only way
# to add a block. Herdr remembers which layout is shown, so this moves a window
# still showing the stock `main` over to the copy and leaves one switched to
# anything else alone. `herdr-app do` talks to the running window; with Herdr
# closed it is skipped, and the next deploy (or ctrl-shift-l) does it.
use_herdr_pip_layout() {
    command -v herdr-app >/dev/null 2>&1 || return 0
    local shown
    shown="$(herdr-app status 2>/dev/null | jq -r '.layout // empty' 2>/dev/null)" || true
    if [ "$shown" = "main" ] && herdr-app do layout.switch '{"name":"main-pip"}' >/dev/null 2>&1; then
        echo "    switched Herdr to main-pip (the layout with Pip in it)"
    fi
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

    # wireplumber reads wireplumber.conf.d once at startup, like the bar reads its
    # QML and hypridle its config. Without this a changed ALSA rule sits there
    # until the next login -- and the one this repo ships decides how many sinks
    # a monitor produces, so "the deploy did nothing" would be the whole symptom.
    # Audio drops for the moment it takes; streams reconnect by themselves.
    #
    # It goes BEFORE the bar, and the settle is load-bearing. The bar binds to
    # the sink nodes wireplumber is publishing when it starts; restarting
    # wireplumber underneath it destroys every one of them, and the bar does not
    # re-resolve Pipewire.defaultAudioSink afterwards -- AudioPill's label is
    # then empty and Pill hides a module with an empty label, so the audio
    # module simply disappears from the bar until something restarts it.
    # Measured on a real deploy: the log filled with "Pipewire error on object N
    # with code -116 no global M any more" for seven nodes, the audio module was
    # gone, and restarting quickshell alone -- nothing else changed -- brought it
    # straight back with a clean log. Starting the bar against a wireplumber
    # that has already finished re-publishing is what makes that unreachable.
    if systemctl --user is-active wireplumber >/dev/null 2>&1; then
        systemctl --user restart wireplumber >/dev/null 2>&1 || true
        sleep 2
        echo "    wireplumber restarted (one HDMI sink per connected display)"
    fi

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

# Brave writes its web app launchers with Exec=/opt/brave-origin-bin/brave-origin,
# which skips /usr/bin/brave-origin and so skips brave-origin-flags.conf. Whichever
# process starts first owns the browser's flags, so opening one of these before the
# browser would silently lose them for the whole session. Brave can rewrite a launcher
# later, and a new web app starts out with the old line: the next run repairs both.
fix_brave_webapp_launchers() {
    local f
    for f in "$HOME"/.local/share/applications/brave-*.desktop; do
        [ -e "$f" ] || continue
        if grep -q '^Exec=/opt/brave-origin-bin/brave-origin ' "$f"; then
            sed -i 's|^Exec=/opt/brave-origin-bin/brave-origin |Exec=/usr/bin/brave-origin |' "$f"
            echo "    ${f##*/}"
        fi
    done
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
    if [ -f "$HOME/.config/brave-origin-flags.conf" ]; then
        \cp -f "$HOME/.config/brave-origin-flags.conf" "$SCRIPT_DIR/brave"
        echo "    brave-origin-flags.conf"
    fi
    # Only the files the repo ships: the rest of herdr-app is Herdr's (deploy_configs).
    # A theme added in the live themes/ is copied in by hand, once, to start shipping it.
    local herdr="$HOME/.config/herdr-app" f
    if [ -f "$herdr/settings.json" ]; then
        \cp -f "$herdr/settings.json" "$SCRIPT_DIR/herdr-app"
        for f in "$SCRIPT_DIR"/herdr-app/themes/*.json; do
            if [ -f "$herdr/themes/${f##*/}" ]; then \cp -f "$herdr/themes/${f##*/}" "$f"; fi
        done
        for f in mods/pip/main.js mods/pip/mod.json layouts/main-pip.json; do
            if [ -f "$herdr/$f" ]; then \cp -f "$herdr/$f" "$SCRIPT_DIR/herdr-app/$f"; fi
        done
        echo "    herdr-app (settings.json + themes + Pip and its layout)"
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
        --gpu-check) setup_gpu_drivers --check; exit 0 ;;
        "")        ;;
        *)         echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac

    install_packages
    setup_gpu_drivers

    migrate_audio_icons
    save_lock_wallpaper
    save_file_manager

    deploy_configs
    remove_orphans
    retire_swaync
    restore_lock_wallpaper

    fix_permissions
    prune_mime_sweep
    ensure_file_manager_default
    fix_brave_webapp_launchers
    check_lid_handling
    enable_services
    apply_system_tweaks
    apply_gtk_theme
    get_wallpapers
    normalize_hyprlock_wallpaper
    setup_superwhisper
    setup_herdr
    use_herdr_pip_layout
    reload_session
    info "Done."
}

# Sourcing this file defines the functions without running anything, which is
# how setup_gpu_drivers is tested against stand-in chwd/sudo commands.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
