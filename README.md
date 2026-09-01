# Linux-Setup

Personal Hyprland desktop configuration for CachyOS/Arch — Hyprland (Lua config),
a quickshell bar, hyprlock/hypridle, swaync notifications, kitty, fish, rofi, a
Catppuccin Mocha GTK theme (thunar and the file chooser) and an SDDM theme.

This repo is the source of truth. The live system is a deployed copy of it, so
**edit the configs here, in `Hyprland_Setup/<app>/`, not in `~/.config/<app>/`** —
a deploy overwrites the live copy.

## Install

Clone anywhere (paths resolve from the repo, not a hardcoded `~/Linux-Setup`) and
run the one entry point:

```sh
git clone <this repo>
./Linux-Setup/Hyprland_Setup/install.sh
```

It installs the packages and deploys the configs, and handles both a first-time
install and a routine update — there is no separate `update.sh`. It prompts, so
run it interactively. Answering yes to "first install" adds the optional extras
(avahi, the `xdg-terminal-exec` symlink, a global git identity, Tailscale, PIA);
answering yes to the wallpaper prompt copies `wallpapers/` into `~/Pictures`.

On anything that is not a first install, the machine-specific values already on
the system — audio sink IDs, the main monitor, the hyprlock background — are
captured before the copy and written back after it, so a deploy cannot break
audio or display on a machine whose hardware differs from the committed values.

## Pulling live changes back

If changes were made directly in `~/.config`, bring them into the repo before a
deploy destroys them:

```sh
./Linux-Setup/Hyprland_Setup/install.sh --pull
```

This adds and overwrites, but never deletes, and it does drag machine-specific
values into the repo — review with `git diff` before committing.

```sh
./Linux-Setup/Hyprland_Setup/install.sh --help
```

## Keys

| Bind | Does |
|---|---|
| `SUPER+RETURN` / `SPACE` / `E` / `B` | terminal / launcher / files / browser |
| `SUPER+W` / `SUPER+SHIFT+W` | wallpaper picker / random wallpaper |
| `SUPER+V` | clipboard history |
| `SUPER+N` | notification centre |
| `SUPER+S` / `SUPER+ALT+S` | screenshot / screenshot to text (OCR) |
| `SUPER+L` / `SUPER+SHIFT+L` | lock / lock and suspend |

`Hyprland_Setup/hypr/modules/binds.lua` is the full list.

## Layout

```
Hyprland_Setup/
  install.sh          the only entry point (deploy + --pull)
  install_lib/        python helpers used BY install.sh; not deployed
  hypr/               hyprland, hyprlock, hypridle + the shell scripts
  quickshell/         the bar, one file per module
  swaync/             notification daemon theme
  gtk-3.0/ gtk-4.0/   Catppuccin Mocha over adw-gtk3-dark (thunar, dialogs)
  fastfetch/ fish/ kitty/ nvim/ rofi/ swappy/ weathr/
  voidsddm/ sddm.conf.d/   SDDM theme (deployed to /usr, needs sudo)
wallpapers/           copied to ~/Pictures/wallpapers on request
*.txt                 personal command reference notes
```

`CLAUDE.md` documents the internals — the preserve mechanism, the bar modules and
the traps found while building them.
