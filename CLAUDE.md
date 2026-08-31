# Linux-Setup

Personal Hyprland desktop configuration for CachyOS/Arch. This repo is the **source of
truth**; the live system is a deployed copy of it.

## The deploy model — read this first

```
Linux-Setup/Hyprland_Setup/<app>/   ──[ install.sh ]──>   ~/.config/<app>/
```

`Hyprland_Setup/install.sh` is the **only** entry point. It installs packages, copies
this repo's configs over the live ones, and re-applies machine-specific values. It
handles both first-time install and routine updates — there is no separate
`update.sh` (it was folded into `install.sh` in commit `4adec1a`; `README.md` still
references it and is stale).

**Always edit configs here, in `Hyprland_Setup/<app>/` — never in `~/.config/<app>/`.**
`install.sh` copies repo → live with `cp -rf`, so any edit made directly in `~/.config`
is silently destroyed the next time it runs. Changes are not live until `install.sh` is
run.

### Where each directory lands

| Repo path | Deployed to |
|---|---|
| `Hyprland_Setup/{fastfetch,fish,hypr,kitty,rofi,swappy,waybar,nvim,swaync,weathr}` | `~/.config/` |
| `Hyprland_Setup/voidsddm` | `/usr/share/sddm/themes` (sudo) |
| `Hyprland_Setup/sddm.conf.d` | `/etc` (sudo) |
| `wallpapers/` | `~/Pictures/` (opt-in prompt, `cp -rn`, never overwrites) |

`Hyprland_Setup/install_lib/` holds Python helpers used *by* `install.sh` and is
deliberately **not** deployed — don't add a copy line for it.

Adding a new app config means creating `Hyprland_Setup/<app>/` **and** adding a matching
`cp` line to `install.sh`; it is not picked up automatically.

## Machine-specific values (the subtle part)

Some deployed files contain values true only for this specific hardware. Blindly
overwriting them breaks audio/display on a machine whose hardware differs from whatever
was last committed. `install.sh` therefore prompts before overwriting, and when the
answer is "no" it captures the live value *before* the copy and writes it back *after*:

| File | Preserved |
|---|---|
| `waybar/scripts/audio-output-toggle.sh` | `BUILT_IN_SINK`, `HEADPHONE_SINK`, `SPEAKER_SINK`, `BLUETOOTH_SINK` |
| `waybar/config` | the `"pulseaudio"` → `"format-icons"` block |
| `hypr/modules/config.lua` | `config.mainMonitor` |

**If you add another hardware-specific value to any config, add it to this
capture/restore list too**, or it will be clobbered on every run.

The restore is done by two helpers, so the brace-matching and line-rewriting logic
exists once each:

- `install_lib/waybar_format_icons.py get|set <file> [value]` — brace-matched extract/
  replace of the `format-icons` block inside the `"pulseaudio"` object.
- `install_lib/replace_line.py <file> <pattern> <replacement> [<pattern> <replacement>…]`
  — replaces whole lines matching a regex. An empty replacement is skipped.

Caution: `replace_line.py` rewrites **every** matching line. `BUILT_IN_SINK` is assigned
twice in `audio-output-toggle.sh` (once at top level, once indented inside the toggle
logic), so its pattern is anchored to column 0 (`^BUILT_IN_SINK`) to avoid corrupting
the indented reassignment. Anchor carefully when adding patterns.

## install.sh conventions

- Runs under `set -euo pipefail` — any failure aborts rather than half-deploying. `grep`
  calls that may legitimately match nothing need `|| true`; conditionally-set variables
  need `${var:-}`.
- Paths resolve from `$SCRIPT_DIR`/`$REPO_ROOT`, not a hardcoded `~/Linux-Setup`, so the
  repo works cloned anywhere.
- Package installs are one `pacman` transaction plus one `paru` transaction. One bad
  package name fails the whole transaction.
- Scripts under `hypr/scripts/` and `waybar/scripts/` are made executable by a `find`
  sweep — new `.sh` files are picked up automatically, no per-file `chmod` to add.
  (Several are committed mode 644, which is why the sweep exists.)
- Because `read` prompts run under `set -e`, the script must be run interactively.

## Not code

The top-level `*.txt` files (`package_management.txt`, `git_command.txt`, `nmcli.txt`,
`tailscale_commands.txt`, etc.) are personal command-reference notes. Editing them has
no effect on the live system.
