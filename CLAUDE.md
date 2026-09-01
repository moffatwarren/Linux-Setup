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
  live. Groups: `audio` (sinks), `machine` (monitor), `wallpaper` (hyprlock background).
- A group listed in `NO_PROMPT_GROUPS` is never asked about — the live value simply wins
  on any run that is not a first install. `wallpaper` is there because the lock screen
  background is a personal choice, not something the repo should ship over.
- Fields split on `|`, so **a regex must not contain a literal `|`**.

Currently preserved: `BUILT_IN_SINK`, `HEADPHONE_SINK`, `SPEAKER_SINK`, `BLUETOOTH_SINK`
in `hypr/scripts/audio-output-toggle.sh`; `config.mainMonitor` in
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
`utils/monitor_utils.lua` (all now fall back to `"quickshell"`). Keeping it means swapping
bars later is still a one-liner, but it is **not** in `PRESERVE`: with waybar gone there
is only one value it can hold, so preserving it only made the `machine` prompt claim to
ask about a choice that no longer exists.

`Hyprland_Setup/quickshell/` has one file per module: `Bar.qml` lays out left/center/right,
`Pill.qml` is the shared rounded-module background, and `Theme.qml` is a `pragma Singleton`
holding the Catppuccin Mocha palette.

`tailscale.sh` and `pia.sh` are driven by `ScriptPill.qml`, which runs them with
`Process` and parses the waybar-style JSON they still print. Audio/battery/network/
bluetooth/workspaces/media use Quickshell's native services instead, so the bar is
event-driven rather than polling.

`ListPopup.qml` is the Catppuccin hover panel used by the audio, bluetooth, battery and
tailscale modules (a title plus `{ text, detail, accent }` rows). It replaced the stock
QtQuick `ToolTip`s, which ignored the palette. Modules drive it with
`requested: root.hovered`, using the `hovered` alias `Pill.qml` exposes. Its optional
`maxDetailWidth` elides the right-hand column, for rows whose detail is a device name
long enough to stretch the panel across the screen (`AudioPill` needs it).

`CalendarPopup.qml` is the clock's hover panel: the current month as a grid, today
picked out with a filled blue disc, with the leading and trailing days of the
neighbouring months dimmed so every week is complete. It borrows `ListPopup`'s frame,
anchoring and 300 ms open delay rather than reusing it — a month is a grid, and
`ListPopup` only stacks rows. Whole weeks that fall entirely outside the month are
dropped, so a short month leaves no blank row. `ClockPill` feeds it a **midnight-
truncated** date: `SystemClock` ticks every second, and a `date` property only signals
a change when the value differs, so the grid rebuilds once a day instead of once a
second. It is display-only — no month navigation, since a hover panel is dismissed by
moving the pointer to reach the arrows.

`WeatherPill.qml` is the current condition and temperature, with `ForecastPopup.qml`
— the week ahead as a table — on hover. Both halves read one `hypr/scripts/`
`weather-forecast.sh` poll, and both draw their glyph from one WMO code table, so
the pill and the panel can never disagree about the weather or the icon for it.

It is **not** a `ScriptPill`, and `weather.sh` no longer has an `--update` case (only
`--openWeather`, still the right-click). wttr.in publishes three days, not seven, and
its one-line format exposes no condition code at all — only an emoji — so a pill fed
from wttr.in could not show the same icon as a panel fed from anywhere else. Both now
come from Open-Meteo (free, no key), which publishes a WMO code for the current hour
and for each day. The location still comes from wttr.in, so only one service does the
IP geolocation. The script also probes `wttr.in/?format=%t` for whether this location
is °C or °F — wttr.in picks that from the location and exposes it nowhere in its JSON
— and asks Open-Meteo for the same unit, so the reading matches what wttr.in would
have said. It prints raw numbers (WMO code, temperature, min/max, precipitation
chance) and leaves the formatting to the QML, like `system-stats.sh`. Weather is
cached for ten minutes (matching both the pill's refresh and Open-Meteo's own update
rate) and the location for a week, so most ticks are a `cat` rather than a request;
on a network failure it prints the stale cache, or nothing at all, and the module
keeps its last good reading rather than blanking.

`WeatherCodes.qml` is the singleton holding that table — WMO code to glyph, short
label and colour. It is a singleton precisely because two things read it. An unmapped
code returns the "N/A" glyph, not a sun. The pill colours only the glyph by condition
and leaves the temperature the bar's normal colour, the way `ScriptPill` colours only
the state word.

`ForecastPopup` borrows `CalendarPopup`'s frame rather than reusing `ListPopup`,
because a forecast day is six aligned columns and `ListPopup` only puts one label
opposite one detail. Its columns are sized from `TextMetrics.advanceWidth` (**not**
`.width`, which is the ink bounding box and is a fraction narrower than the space the
same string lays out in — every condition elided by one pixel), so the table does not
reflow as the numbers change width.

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

`PowerProfilePill.qml` carries the machine's vitals in its hover panel — CPU and memory
use, GPU load and VRAM, root filesystem use, and CPU/GPU temperature — because none of
those warrant a pill of their own. `hypr/scripts/system-stats.sh` gathers everything but
the CPU figure and prints one JSON object of raw numbers (bytes, percent, millidegrees),
leaving all formatting to the QML. It discovers sensors by **name, not index**: hwmon
numbering is assigned in probe order and changes between boots, and the DRM card index
moves the same way. A value it cannot read is omitted from the JSON rather than reported
as `0`, so the panel drops that row instead of showing a confidently wrong reading. That
script runs on a 2 s timer gated on `hovered`, with one immediate read on hover, so an
idle bar spawns no processes.

CPU utilisation is the exception, because `/proc/stat` counts jiffies since boot and so
only yields a percentage as a **delta between two samples** — there is nothing to read
once. It is sampled in the QML with `FileView` (the `NetworkPill` throughput pattern: no
process, so it can run continuously) and differenced, which is also what lets the panel
open with a real number instead of a row that appears two seconds later. Two traps: a
`reload()` hands back the *previous* contents once at startup, so a zero total-delta must
be skipped rather than divided by, and `idle` is fields 4+5 (idle **and** iowait).

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
  and the speakers are USB, and other machines invert that. Its hover panel names the
  default output and input (`Pipewire.defaultAudioSink`/`defaultAudioSource`, shown by
  `description` with `nickname`/`name` as fallbacks) plus each one's volume; both nodes
  go in the `PwObjectTracker` so those stay live.
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
