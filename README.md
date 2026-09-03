# Linux-Setup

Personal Hyprland desktop configuration for CachyOS/Arch — Hyprland (Lua config),
a quickshell bar with matching app launcher / clipboard / wallpaper overlays
and notifications, hyprlock/hypridle, kitty, fish, a Catppuccin Mocha GTK
theme (thunar and the file chooser) and an SDDM theme. Everything that
draws is Catppuccin Mocha — the bar, the terminal, GTK apps, btop, neovim,
the lock screen and the login screen.

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
the system — the main monitor and the hyprlock background — are captured before
the copy and written back after it, so a deploy cannot break display on a machine
whose hardware differs from the committed values. Audio used to be on that list;
its settings live in the bar's audio menu now, under `~/.cache`, where a deploy
never reaches them. Updating a machine that predates that carries its old
headphone and bluetooth sinks across into the menu as icons, once, so nothing
has to be set up again.

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
| `SUPER+K` | this keybind list, on screen |
| `SUPER+N` / `SUPER+SHIFT+N` | notification centre / mute notifications |
| `SUPER+S` / `SUPER+ALT+S` | screenshot / screenshot to text (OCR) |
| `SUPER+CTRL+S` | record a region — press again to stop |
| `SUPER+L` / `SUPER+SHIFT+L` | lock / lock and suspend |
| `SUPER+O` | next audio output |

`Hyprland_Setup/hypr/modules/binds.lua` is the full list, and `SUPER+K` puts a
readable copy of it on screen.

The bar is also the notification daemon — there is no separate one. The bell
module, right of the network one, shows whether notifications are muted and how
many are unread; clicking it opens the list, and right-clicking it mutes.

Clicking the audio module opens the output and input picker; right-clicking it
mutes. Each output has a switch beside it, and `SUPER+O` steps through the ones
switched on — so a monitor's HDMI audio can be left out of the rotation without
being hidden. Inputs take a radio button, since only one can be the default.

Clicking an output's icon opens a small palette — volume, speakers, headphones,
bluetooth, display, TV — and that becomes its icon in the bar and in the popup
`SUPER+O` raises. Worth setting once: nothing can tell headphones from speakers
by the sink name, so a wired headset otherwise just gets the generic volume icon.

All of it is remembered, including for a device that is unplugged.

`SUPER+CTRL+S` selects a region and starts recording it. A red pill with the
elapsed time appears in the bar while it runs, and stops the recording when
clicked — as does pressing `SUPER+CTRL+S` again. Recordings land in
`~/Videos/recordings`, and the path of a finished one is put on the clipboard.

The launcher, the clipboard history and the wallpaper picker are one interface
in three guises — the same quickshell overlay, living in the bar process. Type
to filter, arrows to move, Enter to pick, Escape to cancel. In the clipboard,
`Delete` (or a right-click) drops an entry.

## Layout

```
Hyprland_Setup/
  install.sh          the only entry point (deploy + --pull)
  install_lib/        python helpers used BY install.sh; not deployed
  hypr/               hyprland, hyprlock, hypridle + the shell scripts
  quickshell/         the bar, the overlays and notifications, one file per module
  gtk-3.0/ gtk-4.0/   Catppuccin Mocha over adw-gtk3-dark (thunar, dialogs)
  btop/ fastfetch/ fish/ kitty/ nvim/ swappy/ weathr/
  voidsddm/ sddm.conf.d/   SDDM theme (deployed to /usr, needs sudo)
wallpapers/           copied to ~/Pictures/wallpapers on request
*.txt                 personal command reference notes
```

`CLAUDE.md` documents the internals — the preserve mechanism, the bar modules and
the traps found while building them.
