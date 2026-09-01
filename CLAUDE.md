# Linux-Setup

Personal Hyprland desktop configuration for CachyOS/Arch. This repo is the **source of
truth**; the live system is a deployed copy of it.

## The deploy model — read this first

```
Linux-Setup/Hyprland_Setup/<app>/   ──[ install.sh ]──>   ~/.config/<app>/
                                    <──[ install.sh --pull ]──
```

`Hyprland_Setup/install.sh` is the **only** entry point. It handles first-time install
and routine updates — there is no separate `update.sh` (folded in at commit `4adec1a`).

```
./install.sh          # install packages + deploy repo configs to the live system
./install.sh --pull   # copy live configs back into the repo, for review + commit
./install.sh --help
```

**Edit configs here, in `Hyprland_Setup/<app>/` — not in `~/.config/<app>/`.** Deploy
uses `cp -rf`, so live edits are destroyed on the next run. If you *have* made live
edits, `--pull` brings them back before you lose them. Changes are not live until
`install.sh` runs.

## Adding things — everything is a list at the top of install.sh

| To add | Edit |
|---|---|
| An app config | `CONFIGS=(…)` — add the directory name, create `Hyprland_Setup/<name>/` |
| A repo package | `PACMAN_PKGS=(…)` |
| An AUR package | `PARU_PKGS=(…)` |
| A preserved machine value | `PRESERVE=(…)` — see below |

A name in `CONFIGS` with no matching directory is skipped with a warning, not a fatal
error. `install_lib/` holds Python helpers used *by* `install.sh` and is deliberately
**not** deployed.

Non-`~/.config` destinations are still explicit in `deploy_configs()`:
`voidsddm` → `/usr/share/sddm/themes`, `sddm.conf.d` → `/etc` (both sudo). Wallpapers
go to `~/Pictures` via an opt-in prompt using `cp -rn` (never overwrites).

## Machine-specific values (the subtle part)

Some deployed files hold values true only for this hardware. Overwriting them breaks
audio/display on a machine whose hardware differs from what was last committed. Before
copying, `install.sh` captures the live values; after copying, it writes them back. The
`PRESERVE` table drives this entirely:

```
"<path under ~/.config>|<regex>|<prompt group>|<handler>"
```

- **handler `line`** — the whole line matching `<regex>` is captured and restored. It is
  the only handler; the `icons` one died with the waybar config it parsed.
- **prompt group** — one y/N prompt per group, asked only if a file in that group exists
  live. Groups: `audio` (sinks), `machine` (monitor + bar choice), `wallpaper` (hyprlock
  background).
- A group listed in `NO_PROMPT_GROUPS` is never asked about — the live value simply wins
  on any run that is not a first install. `wallpaper` is there because the lock screen
  background is a personal choice, not something the repo should ship over.
- Fields split on `|`, so **a regex must not contain a literal `|`**.

Currently preserved: `BUILT_IN_SINK`, `HEADPHONE_SINK`, `SPEAKER_SINK`, `BLUETOOTH_SINK`
in `hypr/scripts/audio-output-toggle.sh`; `config.mainMonitor` and `config.bar` in
`hypr/modules/config.lua`; the `path =` line of `hypr/hyprlock.conf` (its only one, in
the `background` block).

**Add any new hardware-specific value to `PRESERVE`**, or it is clobbered every run.

**If a preserved file ever moves, add it to `LEGACY_MOVES`.** A machine still running the
previous layout does not have the new path yet, so its group is never prompted for, nothing
is captured, and the committed values silently replace the machine's own.
`migrate_legacy_paths()` seeds the new path from the old one before the capture step. This
is how `waybar/scripts/audio-output-toggle.sh` → `hypr/scripts/audio-output-toggle.sh`
survives on a machine upgrading from the waybar era. It only copies when the new path is
absent, so a machine already on the current layout is untouched by a stale old copy.

Two hazards when adding patterns:

- `replace_line.py` rewrites **every** matching line. `BUILT_IN_SINK` is assigned twice
  in `audio-output-toggle.sh` (top level, and indented inside the toggle logic), so its
  pattern is anchored to column 0 (`^BUILT_IN_SINK`). Anchor carefully.
- The restore helper lives in `install_lib/`:
  `replace_line.py <file> <pattern> <replacement> …` (empty replacement = skip).

## The bar (quickshell)

**waybar has been removed** — its config, CSS and package are gone, and `quickshell` is
the only bar. Its four helper scripts were still load-bearing, so they moved to
`hypr/scripts/` (a bar-neutral home that is already deployed and already gets the
`chmod +x` sweep): `audio-output-toggle.sh`, `tailscale.sh`, `pia.sh`, `weather.sh`.
`media.sh` was deleted outright — MPRIS replaced it. The waybar config, its CSS and the
old script paths are recoverable from commit `45cf455` if a codepoint or format string
is ever needed.

`config.bar` in `hypr/modules/config.lua` still selects which bar launches, read by
`autostart.lua`, the `SUPER+R` bind in `binds.lua`, and the monitor-hotplug restart in
`utils/monitor_utils.lua` (all now fall back to `"quickshell"`). It is in `PRESERVE`, so
the choice survives updates — keeping it means swapping bars later is still a one-liner.

`Hyprland_Setup/quickshell/` has one file per module: `Bar.qml` lays out left/center/right,
`Pill.qml` is the shared rounded-module background, and `Theme.qml` is a `pragma Singleton`
holding the Catppuccin Mocha palette.

`tailscale.sh`, `pia.sh` and `weather.sh` are driven by `ScriptPill.qml`, which runs them
with `Process` and parses the waybar-style JSON they still print. Audio/battery/network/
bluetooth/workspaces/media use Quickshell's native services instead, so the bar is
event-driven rather than polling.

`ListPopup.qml` is the Catppuccin hover panel used by the bluetooth, battery and
tailscale modules (a title plus `{ text, detail, accent }` rows). It replaced the stock
QtQuick `ToolTip`s, which ignored the palette. Modules drive it with
`requested: root.hovered`, using the `hovered` alias `Pill.qml` exposes.

`WifiMenu.qml` is the right-click dropdown on the network module: a scrollable-free
list of nearby SSIDs (deduplicated per SSID, strongest first, capped at 8), each with a
four-bar signal meter, a lock for secured networks and a "saved" marker for known ones.
Left-click a row to connect (`connect()`, or `connectWithPsk()` behind an inline
password field for a secured network never joined before), right-click a saved row to
`forget()` it. The header toggles `Networking.wifiEnabled`, and an "Open nmtui…" footer
keeps the old escape hatch. Scanning is driven by a `Binding` on the device's
`scannerEnabled` tied to whether the menu is open, so it only scans while visible.

The signal meter is drawn with rectangles rather than a nerd font glyph — no private-use
codepoint to get wrong, and it scales with the strength value (which is 0..1, not 0-100).

`PowerPill.qml` is the rightmost module: a power button whose **left**-click opens
`PowerMenu.qml` (Lock, Sleep, Log out, Restart, Shutdown). Left-click rather than
right-click because opening the menu is the button's only purpose. The commands mirror
the equivalent keybinds in `binds.lua` — in particular Sleep locks before suspending
(`hyprlock & sleep 0.5 && systemctl suspend`), matching `SUPER+SHIFT+L`, rather than
suspending an unlocked session. The action list is a plain array at the top of
`PowerMenu.qml`, so adding or removing an entry is one line.

`BluetoothMenu.qml` is the right-click dropdown on the bluetooth module, built to match
`WifiMenu`: paired devices first (click to connect/disconnect, right-click to forget),
then a "Nearby" section of discovered devices (click to pair). The header toggles the
adapter and shows a scanning indicator, and "Open blueman…" remains as the escape hatch.
Discovery is scoped to the menu being open via a `Binding` on the adapter's `discovering`,
so the radio is not scanning all day.

Both dropdowns dismiss on a click anywhere outside via `HyprlandFocusGrab` (`windows: [root]`,
`active: root.open`, `onCleared: close()`). A layer-shell popup receives no event for an
outside click on its own, so without the grab the only way to close the menu was to
right-click the module again. The grab coexists with `WifiMenu`'s `grabFocus`, which the
password field needs for keyboard input — verified that revealing the field does not
clear the grab and dismiss the menu.

Devices whose name is a bare MAC are filtered out — they are BLE beacons and there are
usually a dozen of them. The row glyph is picked from the device's freedesktop `icon`
(`input-gaming` → gamepad, `audio-*` → headphones, `phone` → phone), falling back to the
bluetooth glyph.

`PiaPill.qml` specialises `ScriptPill` the same way: `pia.sh` still drives the state and
the label, while a `piactl` call fills a hover panel with where the tunnel exits.
`piactl get region` reports the *selected* region, which is usually `auto` and so says
nothing about where you landed. `hypr/scripts/pia-region.sh` resolves the real one by
matching the exit IP against PIA's own published server list (first party, no
geolocation service), cached in `~/.cache/pia-serverlist.json` and refreshed weekly, so
the Region row reads e.g. `US Seattle  (auto)`. It prints nothing rather than guessing:
a /24 is shared by more than one region about a quarter of the time and a few of those
span countries (`82.139.195.0/24` is both Algeria and Egypt), so an exact IP match wins
and an ambiguous subnet is reported as unknown. `vpnip`/`pubip` rows are dropped when
piactl returns `Unknown`. Disconnected shows "Not connected" in red plus the real
public IP.

`TailscalePill.qml` specialises `ScriptPill` because it needs both halves of waybar's
format (`Tailscale: {icon} | Exit-node: {text}`) and reads its peer list from
`tailscale status --json` directly, rather than from the script's tooltip.

`ScriptPill.altColors` maps the script's `alt` field to a Catppuccin colour for the
**state word only** (green connected / yellow connecting / red disconnected), leaving
the `Tailscale:` and `PIA:` prefixes neutral — the equivalent of waybar colouring
`#custom-pia` by its class. It works by switching `Pill.richText` on and wrapping the
word in `<font color>`, so the palette in `Theme.qml` is stored as **strings**: QML
converts them to `color` on assignment, and they can also be interpolated into markup.

Six things to know before editing the QML:

- **Nerd font icons must be written as `\uXXXX` escapes.** The glyphs are private-use
  codepoints; pasting them literally silently produces empty strings, which makes the
  pill vanish (`Pill` hides itself when its label is empty). Take codepoints from an
  existing module or from `git show 45cf455^:Hyprland_Setup/waybar/config`, rather than
  retyping the character.
- **Quickshell services are lazy.** `Hyprland.workspaces`, `Networking.devices` and
  `Bluetooth.devices` stay empty until something actually binds to them; the modules
  hold a property referencing the service for this reason. Pipewire additionally needs
  `PwObjectTracker` for live volume/mute updates.
- **`NetworkDevice.address` is the MAC, not the IP** — no IP is exposed anywhere on the
  device, so `NetworkPill` shells out to `ip -4 -br addr` when the active device changes.
  Networking exposes no byte counters either, so the hover panel's up/down rates come
  from `/sys/class/net/<iface>/statistics/{rx,tx}_bytes`, sampled once a second with
  `FileView` (no process spawn) and differenced. The baseline resets on an interface
  change so the first sample cannot report a bogus spike.
- `AudioPill` reads which sink is headphones/bluetooth out of
  `hypr/scripts/audio-output-toggle.sh` rather than guessing from the sink name.
  Inferring it does not work: on this machine the headphones are the PCI analog jack
  and the speakers are USB, and other machines invert that.
- **`ScriptPill` must escape control characters before `JSON.parse`.** `tailscale.sh`
  joins its peer list with raw carriage returns, which are illegal inside a JSON string;
  parsing them threw and blanked the module the instant tailscale came up. It also keeps
  the last good value on a parse error rather than clearing.
- **Bind `visible`, don't set it from `onXChanged`.** A handler never fires for a
  property that is already true at construction, which is why `ListPopup` gates
  visibility through a bound `delayPassed` flag.

Not carried over from waybar: the clock's `{calendar}` tooltip is a plain date, and
`format-alt` click-to-cycle is not implemented.

Media: click the album art or the title to play/pause, double-click either to skip.
`clicked` arrives before `doubleClicked`, so the single-click action is held in a 250 ms
timer that a double-click cancels — otherwise every skip would also toggle playback.

## install.sh conventions

- Runs under `set -euo pipefail` — failures abort rather than half-deploying. `grep`
  calls that may legitimately match nothing need `|| true`; conditionally-set variables
  need `${var:-}`.
- **Never call `read -p` inside a `while read … < <(…)` loop** — the loop redirects
  stdin and the prompt silently consumes the loop's data instead of user input. This
  already caused a real bug; `prompt_preserve_groups` uses `mapfile` into an array for
  exactly this reason.
- Paths resolve from `$SCRIPT_DIR`/`$REPO_ROOT`, never a hardcoded `~/Linux-Setup`, so
  the repo works cloned anywhere.
- Packages install as one `pacman` transaction plus one `paru` transaction. One bad
  package name fails the whole transaction.
- `*.sh` under any deployed `<app>/scripts/` is made executable by a `find` sweep — new
  scripts need no per-file `chmod`. (Several are committed mode 644, hence the sweep.)
- Prompts mean the script must be run interactively.

## First-install extras

Behind the "first install" prompt, each individually optional: avahi-daemon, the
`xdg-terminal-exec` → kitty symlink, gnome-text-editor whitespace, global git identity,
Tailscale (Arch package + `tailscaled`, rather than the upstream `curl | sh`), and PIA
(`piavpn-bin` + service). The interactive tails — `tailscale up` browser auth, PIA app
login — are printed as instructions, since they can't be automated.

## Not code

The top-level `*.txt` files are personal command references. The automatable parts of
`tailscale_commands.txt` and `pia_install.txt` are now in `install.sh`; the rest
(`git_command.txt`, `hypctl_commands.txt`, `nmcli.txt`, `systmctl_command.txt`,
`write_iso_commands.txt`, and the troubleshooting half of `package_management.txt`) are
lookup notes and deliberately stay manual. `README.md` is stale — it still references
the removed `update.sh`.
