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
| A **retired** config path | `ORPHANS=(…)` — see below |

A name in `CONFIGS` with no matching directory is skipped with a warning, not a fatal
error. `install_lib/` holds Python helpers used *by* `install.sh` and is deliberately
**not** deployed.

**Deleting something from the repo does not delete it from the machine.**
`deploy_configs` copies with `cp -rf`, which adds and overwrites but never removes, so a
dropped config lives on under `~/.config` looking exactly as live as the rest. Whenever
you retire a deployed file or directory, add its `~/.config`-relative path to `ORPHANS`;
`remove_orphans()` runs straight after the deploy and `rm -rf`s each one. Two guards in
that loop matter: an empty entry is skipped (it would expand to `~/.config` itself), and a
path the repo *still ships* is skipped with a note — without which a stale entry would
silently delete what `deploy_configs` wrote one step earlier and the config would just stop
existing. Beyond that, entries are removed unconditionally, so list only paths this repo
put there.
Currently retired: `rofi`, `swaync`, `hypr/scripts/clipboard-menu.sh`,
`hypr/scripts/wallpaper-selector.sh`, `hypr/modules/utils/wallpaper_utils.lua` and the two
`noctalia.css`. `ORPHANS` never uninstalls a *package* — `install.sh` only ever installs.

Non-`~/.config` destinations are still explicit in `deploy_configs()`:
`voidsddm` → `/usr/share/sddm/themes`, `sddm.conf.d` → `/etc` (both sudo). Wallpapers
go to `~/Pictures/wallpapers` via an opt-in prompt using `cp -rn` (never overwrites).

Both of those copies `mkdir -p` their destination first, for the same reason: `cp -r
src dest` creates `dest` **as a copy of `src`** when `dest` does not exist. A machine
without `/usr/share/sddm/themes` aborts the deploy half-done under `set -e`; one without
`~/Pictures` silently ends up with the images loose in `~/Pictures`, where neither
`WallpaperPicker.qml` nor `wallpaper-random.sh` — both of which read
`~/Pictures/wallpapers` — can see them.

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

The panel's footer says how old the reading is, and **double-clicking the pill**
re-fetches immediately (`weather-forecast.sh --force`, which sets `FORECAST_MAX_AGE=0`
so the age check can never pass). The age comes from the script, as `updated` — the
**cache file's mtime**, not the time of the poll that read it. Almost every poll is
served from the ten-minute cache, so a QML-side "last fetched" clock would report when
the bar last ran a `cat`; the mtime is when the data actually arrived, and it survives a
bar restart. It is also what makes a failed refresh legible: the script prints the stale
cache on a network error, so the footer keeps showing the old age instead of claiming to
have just updated. `Process.command` is bound to a `force` flag, so `refresh()` must not
fire while the process runs — a second double-click mid-fetch is ignored. The footer's
"N min ago" is re-rendered by a 30 s timer gated on the popup being visible.

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
  go in the `PwObjectTracker` so those stay live. Its glyphs are Material Design Icons
  from the nerd font (volume off/low/medium/high, mute, headphones, bluetooth-audio) —
  **not** the speaker/headphone emoji it used to draw. A real emoji codepoint is served
  by the colour emoji font, which ignores `labelColor` and renders a glossy multicolour
  blob beside the flat monochrome glyphs of every other module.
- **`ScriptPill` must escape control characters before `JSON.parse`.** `tailscale.sh`
  joins its peer list with raw carriage returns, which are illegal inside a JSON string;
  parsing them threw and blanked the module the instant tailscale came up. It also keeps
  the last good value on a parse error rather than clearing.
- **Bind `visible`, don't set it from `onXChanged`.** A handler never fires for a
  property that is already true at construction, which is why `ListPopup` gates
  visibility through a bound `delayPassed` flag.

`NotificationPill.qml` sits between `NetworkPill` and `PowerProfilePill`: a bell showing
whether notifications are muted and how many are unread, opening the notification centre
on click. The bar is the notification daemon now, so that module and the popups it shares
a service with have a section of their own — see **Notifications (quickshell)** below.

Not carried over from waybar: the clock's `{calendar}` tooltip is a plain date, and
`format-alt` click-to-cycle is not implemented.

Media: clicking either the album art or the title opens `MediaMenu.qml` — the cover at
a size worth looking at, above previous / play/pause / next, in the same
`base`-inside-`surface1` frame as `PowerMenu`/`BluetoothMenu`, dismissed by Escape or a
click outside via `HyprlandFocusGrab`. The cover is masked to a rounded square by the
same `MultiEffect` the 22px pill circle uses, and is drawn at the panel width **or at the
artwork's own resolution, whichever is smaller** — it is never upscaled. A Chromium
player publishes a 120–150px cover, and stretching that across the panel is a visibly
interpolated square; a player with real artwork still fills the full width, and the panel
keeps its own width either way, so the menu does not resize per track. **`sourceSize` is
deliberately unset**: under `PreserveAspectCrop` it is a decode *target*, not a cap, so Qt
scales a 120px cover **up** to meet it and `implicitWidth` then reports the request rather
than the artwork — which is the one number that sizing rule needs. (Under the default fill
mode it really is a cap, which is what makes this worth writing down.)

It replaced click-to-toggle plus double-click-to-skip: `clicked` arrives before
`doubleClicked`, so the single click had to sit in a 250 ms timer and every skip toggled
playback on its way through. A button is greyed to `overlay0` and inert when the player
says its `canGoPrevious`/`canGoNext`/`canTogglePlaying` is false, and the menu closes
itself when `player` goes null — the module hides when nothing is playing, and a menu left
open would hang off an invisible anchor.

## The overlays — launcher, clipboard, wallpapers (SUPER+SPACE / V / W)

**rofi is gone from the repo entirely** — `Hyprland_Setup/rofi/`, the `rofi`
entry in `CONFIGS` and in `PACMAN_PKGS`, and `config.menu` in
`hypr/modules/config.lua` all went with it, because it drew all three of these
menus and now draws none. `hypr/scripts/wallpaper-selector.sh` (a `rofi -dmenu
-show-icons` grid) is gone, and so is `hypr/modules/utils/wallpaper_utils.lua`,
whose `set_random` duplicated the apply logic in Lua and ran
`io.popen`/`os.execute` synchronously on Hyprland's config thread.
`clipboard-menu.sh` — the `rofi -dmenu` clipboard list — is replaced by
`hypr/scripts/clipboard-history.sh` (below). All four of those paths are in
`install.sh`'s `ORPHANS` list, which is what removes them from a machine
upgrading from the rofi layout; the rofi *package* is left installed, since
`install.sh` uninstalls nothing.

`OverlayPanel.qml` is the one window all three wear: dimmed backdrop, a centred
`base` card in a `surface1` border, a lavender title with a subtitle and a count
beside it, a `surface0` filter box under that, and a hint line along the bottom.
`WallpaperPicker.qml`, `AppLauncher.qml` and `ClipboardMenu.qml` supply only the
body — a filmstrip, a list of apps, a list of clipboard entries.

The **geometry** lives in `OverlayPanel` for the same reason the colours do. The
padding, the 58px header and the gaps above the body and the footer are what make
two overlays look like the same menu; three private copies would drift apart the
first time one was adjusted. A consumer sets `panelWidth` and `bodyHeight` and
gets everything else.

Children are declared in the consumer's file and land in the panel's body via
`default property alias content: body.data`, so they can freely reference that
file's ids (including its root `OverlayPanel`) — which is how the wallpaper
picker's `panelWidth` can be derived from its own grid.

Keyboard flows one way: the filter box holds focus and owns every keystroke.
`OverlayPanel` claims Escape (close) and Enter (`accepted()`), then offers the
rest to the body as `navKey(event)`; a body **sets `event.accepted`** for the
keys it handles (arrows, Home/End, Delete) and lets everything else fall through
and type into the box. There is no second focus item to fight over.

All three live **inside the bar process**, not in a `qs -p` of their own, so
opening one is instant and decoded thumbnails stay in Qt's pixmap cache between
openings. `shell.qml` holds each in a `LazyLoader` (`loading: true`, built in the
background at startup) beside an `IpcHandler`; the keybinds are just `qs ipc call
{wallpaper,launcher,clipboard} toggle`. The bar is the only quickshell instance
and runs the default config path, so `qs ipc call` finds it with no `-c`.
**Opening one closes the other two** (`closeOverlays()` in `shell.qml`): each
takes the keyboard with `WlrKeyboardFocus.Exclusive`, and two exclusive layer
surfaces up at once leaves the keystrokes going to whichever the compositor
happened to pick.

### The app launcher (SUPER+SPACE)

Applications come from Quickshell's own `DesktopEntries` scanner, so there is no
`.desktop` parsing here and `entry.execute()` honours Exec field codes,
`Terminal=true` and the startup working directory. `noDisplay` entries are
dropped.

`score()` ranks a match rather than just filtering: a prefix of the name (0)
beats a hit at a word boundary inside it (1), which beats one mid-word (2),
which beats `genericName` (3), `keywords` (4), `comment` (5) and finally
`execString` (6) — the last being how you find an app you only know by its binary
name. Ties break on launch count, then alphabetically.

Launch counts persist in `~/.cache/quickshell-launcher.json` via `FileView`
(`printErrors: false` — it does not exist until the first launch, and that is not
worth an error on every bar startup). An empty query is therefore the most-used
apps in order, which is what `rofi -show drun` did; dropping it would have been a
downgrade.

`launch()` **closes the overlay before calling `execute()`**, so the exclusive
keyboard grab is gone by the time the new window maps and asks for focus.

### The clipboard history (SUPER+V)

`hypr/scripts/clipboard-history.sh` is the whole backend — `--list` (JSON,
newest first), `--copy <id>`, `--delete <id>`. No cliphist output is parsed in
QML. Image entries carry a cached thumbnail path instead of cliphist's
`[[ binary data 547 KiB png 998x608 ]]` placeholder; thumbnails live in
`~/.cache/cliphist-thumbs` keyed by the cliphist id (never reused, so a cached
file cannot go stale) and are pruned against the live history on each `--list`.

Three things in that script are load-bearing:

- **Only the binary lines are ever read into a shell variable.** Clipboard text
  is arbitrary bytes and a bash string cannot hold a NUL, so slurping the whole
  history into one truncates entries *and* warns about it on every run. The text
  entries only travel down a pipe into `jq`, which keeps them intact.
- **`grep` needs `-a`.** With a NUL anywhere in the history it decides the input
  is binary and prints "binary file matches" instead of the lines.
- **`$ids | index(.id)` does not work in jq** — the pipe rebinds `.` to the array,
  so `.id` is looked up on it and the whole program dies with "Cannot index array
  with string". Hoist the argument out first (`.id as $id`).
- `${f##*/}`, not `basename`, in the prune loop. A few dozen cached thumbnails is
  a few dozen forks otherwise, and that was the entire cost of a `--list` (1.0s
  down to 0.02s).

`Delete` (and a right-click) removes an entry and leaves the menu open, so a run
of junk can be cleared without reopening between each one. The row disappears
from the model immediately and the reload afterwards reconciles with what
cliphist actually holds — waiting for the process to return would make the key
feel dead.

`install.sh`'s `ORPHANS` list is what deletes the old `clipboard-menu.sh` from a
machine upgrading from the rofi layout — `cp -rf` never removes files the repo
has dropped.

### The wallpaper picker (SUPER+W)

A full-screen overlay holding a **single row** of large thumbnails that
**scrolls sideways** — a filmstrip. `flow: GridView.FlowTopToBottom` with the
view's height set to exactly one `cellHeight` is what pins it to one row; columns
then run off the right edge. Up/Down would step *within* a column, so in a one-row
grid they are dead keys; they page by a screenful instead, as PageUp/PageDown do.

`columns` derives the panel width from whole cells only, because a partly-visible
tile at the right edge reads as a rendering glitch rather than as "there is more
this way". Tile size is the two constants `grid.cellWidth`/`cellHeight` (roughly
16:9, since that is what a wallpaper is); everything else follows from them.

`hypr/scripts/wallpaper-set.sh <path>` is the one place a wallpaper is applied —
`awww img` plus the `path =` rewrite in `hyprlock.conf`, so the lock screen
follows the desktop. `wallpaper-random.sh` (SUPER+SHIFT+W) and the picker both
`exec` it. That `path =` line is the same one `PRESERVE` protects (group
`wallpaper`, in `NO_PROMPT_GROUPS`), so a deploy does not undo a pick.

### Five traps shared by the three bodies

- **A per-row/per-tile `MouseArea` cannot drive hover selection.** Arrow keys
  scroll the view, which drags items under a stationary pointer, and the
  synthetic hover that produces yanks the cursor straight back off the item the
  keyboard just moved to. One stationary `MouseArea` anchored over the view
  resolves the index with `view.indexAt(x + contentX, y + contentY)` instead. It
  must be a **sibling** of the `GridView`/`ListView` — a child goes into the
  flickable's content item and scrolls with it, reintroducing the bug.
- Mapping the window in still delivers one motion event for wherever the pointer
  already was, so the hover surface ignores the first event and any that has not
  actually moved; otherwise the opening selection is thrown away before it is
  seen.
- **The wallpaper picker's `Behavior on contentX` must be suppressed for the
  opening jump.** Animating contentX from 0 to column 200 walks the view through
  every position in between, and each frame queues a screenful of thumbnails the
  loader then chews through before it reaches the ones actually on screen.
  `selectCurrent()` sets `grid.jumping` around `positionViewAtIndex` for exactly
  this.
- Qt decodes only jpg/png/gif out of the box; `qt6-imageformats` (in
  `PACMAN_PKGS`) adds webp and avif. A tile whose image fails falls back to its
  filename, so a missing decoder does not look like a thumbnail that never loaded.
- The current wallpaper is read from `hyprlock.conf` with a `FileView`, not from
  `awww query` — same value, no process. It marks that tile with a green dot and
  is where the cursor lands on open.

## Notifications (quickshell)

**swaync has been removed** — its config, CSS and package entry are gone, and the bar is
the notification daemon. Only one process can own `org.freedesktop.Notifications`, and
swaync's own interface (`org.erikreider.swaync.cc`) publishes a count and a DND flag but
no way to ask it what the notifications *say* — so a bar module that lists them has to be
the server. `~/.config/swaync` is in `ORPHANS`; the swaync *package* is left installed,
since `install.sh` uninstalls nothing. The old stylesheet is recoverable from commit
`5168f36` if a colour or a padding value is ever wanted back.

Four files, all in `Hyprland_Setup/quickshell/`:

- `NotificationService.qml` — a `pragma Singleton` wrapping `NotificationServer`. It owns
  the state; the other three only read it.
- `NotificationPill.qml` — the bar module, immediately right of `NetworkPill`.
- `NotificationMenu.qml` — the centre: the list plus the mute toggle.
- `NotificationToasts.qml` — the popups, including the volume/brightness OSDs.

### The two lists

`NotificationService` keeps **`entries`** (what the menu shows, kept until dismissed —
this is "unread") and **`popups`** (what is on screen right now, dropped on a timer)
separately. A notification leaves `popups` when its toast times out and stays in
`entries`, which is the whole difference between "you missed it" and "it is still
shouting at you". The timeouts are the ones the swaync config used — 8 s, 3 s for low,
and critical never expires.

Quickshell **destroys a notification as soon as the `notification` signal handler
returns** unless something sets `tracked`. Everything here is tracked, including an OSD,
which is then dropped explicitly when its toast expires — so a leak shows up as a
notification that will not clear, not as one that vanishes.

### OSDs are not messages

`volume-notify.sh`, `brightness-notify.sh` and `audio-output-toggle.sh` all send
`-h string:x-canonical-private-synchronous:…`. That hint is the marker for "status
readout", and it does two things: a new one **replaces** the popup carrying the same tag
rather than stacking (holding the volume key leaves one card counting up, not thirty),
and the reading never joins `entries` — a volume tap is not something to review later.
The spec's own `transient` hint counts the same way.

`notify-send` sends no `replaces_id`, so without that hint there is nothing else to
deduplicate on. Both it and `value` — the 0-100 that draws the progress bar — have no
dedicated property on `Notification` and must be listed in the server's **`extraHints`**
or they never arrive.

**DND silences apps, not your own keypresses.** An OSD still pops while muted, and so
does a critical notification; everything else is recorded silently. swaync suppressed
all three, which made the volume keys feel broken while muted. The flag is persisted to
`~/.cache/quickshell-notifications.json`, so a mute survives a bar restart.

### Retiring swaync is a deploy step, not just a deleted directory

`ORPHANS` removes `~/.config/swaync` and `autostart.lua` no longer starts it, and on a
machine upgrading from the swaync layout **neither is enough**. `retire_swaync()` in
`install.sh` runs between `remove_orphans` and `reload_session` and closes two holes:

- swaync is still **running**, started by the old `autostart.lua` at login, and still
  holds `org.freedesktop.Notifications`. The bar `reload_session` restarts a moment later
  cannot claim the name, so it comes up with a bell that never receives anything — which
  reads as the new module being broken rather than as a leftover daemon. It is `pkill`ed.
- `/usr/share/dbus-1/services/org.erikreider.swaync.service` declares
  **`Name=org.freedesktop.Notifications`**. Any `notify-send` issued while the name is
  unowned — the gap between login and the bar registering, or the second `reload_session`
  spends restarting it — D-Bus-activates swaync, which then keeps the name for the rest of
  the session. Verified: with the unit unmasked, one `notify-send` against an unowned name
  starts swaync every time. Both of swaync's `.service` files delegate to
  `SystemdService=swaync.service`, so `systemctl --user mask swaync.service` is what shuts
  the activation path (no sudo, undo with `unmask`).

The function is guarded on `command -v swaync`, so it is a no-op on a new machine, and it
does not uninstall the package — `install.sh` never uninstalls.

`reload_session` finishes with `check_notification_owner`, which polls
`busctl --user status org.freedesktop.Notifications` for up to five seconds and names the
owner. Losing the bus name is otherwise a *silent* failure — an empty bell and popups in
the wrong style — so it is worth a line of output saying who actually has it.

### Things that bit, in order

- **`ExclusionMode.Ignore` means "ignore *other* surfaces' exclusive zones" as well as
  "claim none".** The toast window used it and drew straight over the bar. It wants
  `ExclusionMode.Normal` with `exclusiveZone: 0`: reserve nothing, but still respect the
  bar's zone, which is what puts the first card below the bar.
- **Hover comes from a `HoverHandler`, not `MouseArea.containsMouse`.** A hovered child
  MouseArea (an action button, the close button) takes the hover away from a MouseArea
  underneath it. That resumed the expiry timer while the pointer was still on the card,
  and — because the close button is only visible on hover — hid the button at the moment
  it was aimed at, which flickers. A handler on the item keeps reporting for the whole
  subtree.
- **The OSD glyph is drawn from the nerd font, not from the `-i` icon.** Those are
  Adwaita `*-symbolic` SVGs: GTK recoloured them from the stylesheet, but Qt renders them
  with the near-black fill baked into the file, which is invisible on a `base` card. The
  icon *name* is still load-bearing — `NotificationToasts.qml` matches `muted` /
  `volume-low` / `volume-medium` / `headphone` / `brightness` in it — so the scripts still
  have to name the right one. The glyphs are the same Material Design ones `AudioPill`
  draws, so the popup and the bar never disagree.
- **`Notification.expireTimeout` is in milliseconds** (verified: `notify-send -t 10000`
  arrives as `10000`), with -1 meaning "server decides" and 0 meaning "never".
- **`closeOverlays()` must not run before the SUPER+N toggle decides.** It closes the
  notification menu too, so calling it unconditionally made every press re-open the menu
  it had just closed. It only runs on the way *open*.
- One toast window, following `Hyprland.focusedMonitor`, **not** a `Variants` over
  screens — two screens would each pop the same notification. `HyprlandMonitor` exposes no
  `screen`, so the match is by name against `Quickshell.screens`.

### The module and its menu

The pill is a bell: outline when there is nothing, filled when there is, struck through
and dimmed to `overlay0` when muted. It goes yellow with a count, red if anything unread
is critical. Left-click opens the menu, **right-click mutes** without opening anything —
the same shortcut/menu split the bluetooth and network modules use — and the hover panel
is the count and the DND state.

The menu is `PowerMenu`'s frame: a header, the Do-not-disturb row with a switch, the
list, and `Clear all`. A row is left-click to run the sender's `default` action (and
clear it), right-click to just clear it, which is the split `ClipboardMenu` uses. Any
other action the sender offered becomes a button. The list is a `ListView` capped at
420px and clipped, so a busy morning cannot produce a menu taller than the screen.

`open` is **not** owned by the menu: `NotificationService.menuMonitor` holds which
monitor's copy is up, because there is one bar per monitor and SUPER+N must open exactly
one of them. `NotificationPill` gets its `monitorName` from `Bar.qml`, the way
`WorkspacesPill` does.

SUPER+N is `qs ipc call notifications toggle` and SUPER+SHIFT+N is
`… notifications dnd`; `close` and `clear` are there too.


## GTK / thunar (Catppuccin Mocha)

`gtk-3.0/` and `gtk-4.0/` theme every GTK app — thunar above all, plus the file
chooser, gnome-text-editor and the portal dialogs — to the same Mocha palette as
`quickshell/Theme.qml`.

**There is no Catppuccin GTK theme installed.** The theme is stock
`adw-gtk3-dark` (`adw-gtk-theme`, in `extra`); it declares every colour it uses
as a named GTK colour, and a user `gtk.css` loads *after* the theme, so
`gtk-3.0/mocha.css` repaints it by redefining those names. Nothing is forked, so
an adw-gtk3 update cannot leave a half-updated theme behind. The upstream
`catppuccin/gtk` was considered and rejected: it is archived, it bakes the accent
into the package, and it puts the theme outside the repo.

`gtk.css` is the entry point (one `@import`) and `mocha.css` is the palette.
Widget rules go in `gtk.css`, below the import — never in `mocha.css`, which is
colour declarations only so the two GTK versions stay diffable against each other.

Surfaces follow the bar: content is `base` (as the bar slab and every hover panel
are), chrome — headerbar, sidebar — is the recessed `mantle`, popovers and cards
step up to `surface0`, and the accent is `blue`, the same one `CalendarPopup`'s
today disc and swaync's normal-urgency stripe use.

Five things to know before editing:

- **The GTK4 palette is declared twice, and both are load-bearing.**
  `@define-color` is what libadwaita ≤ 1.5 reads; the `:root { --window-bg-color:
  … }` custom properties are what GTK 4.16+ actually resolves. Set only one and
  you get a half-recoloured window whose broken half depends on the installed
  libadwaita. GTK3 has no `:root` form — don't add one there.
- **`.sidebar` alone does not colour thunar's shortcuts pane.** The pane *does*
  carry the class, but it is a `GtkTreeView`, and a treeview paints the `view`
  background (`@theme_base_color`) over it — so the sidebar came out the same flat
  base as the file list. `gtk-3.0/gtk.css` has a `.sidebar treeview.view` rule for
  exactly this. The false negative is worth remembering: probing with
  `.sidebar { background: magenta }` looked like "the class doesn't match",
  because the only magenta that showed through was where the translucent row
  selection composited against it.
- **`headerbar_bg_color` does nothing for thunar** — it has a menubar and toolbar
  in a plain window, not a `GtkHeaderBar`, so its top chrome is `window_bg_color`.
  The setting is not dead; it is what colours the apps that *do* use a headerbar.
- **The GTK3 legacy names are set explicitly even though adw-gtk3 derives them.**
  Thunar's `GtkTreeView`/`GtkIconView` read `theme_base_color` and friends
  directly. Redundant today, and a cheap hedge against adw-gtk3 rearranging its
  own derivations.
- **Folder icons are images; CSS cannot touch them.** They are the dominant
  colour in a file manager, so `papirus-folders -C cat-mocha-blue --theme
  Papirus-Dark` recolours them, from `apply_gtk_theme()` rather than
  `first_install_extras` — it is how a new machine gets the colour at all, and it
  is idempotent. It does *not* need to run to survive a `papirus-icon-theme`
  upgrade (which does reset the folder symlinks it owns):
  `papirus-folders-catppuccin-git` ships a `PostTransaction` pacman hook that
  re-applies the last used colour. Call it **without** `sudo` — it re-execs
  itself under sudo and forwards `USER_HOME`/`XDG_DATA_DIRS` in the process.
  Note it both *provides* and *conflicts with* plain `papirus-folders`, so
  listing both in `PARU_PKGS` fails the whole transaction.
- **The `papirus-folders` call is wrapped in an `if`, and must stay that way.**
  It calls `fatal` for a colour the installed theme lacks, and its sudo re-exec
  fails on a declined password prompt. Either one, under `set -e`, aborts the
  deploy *after* `deploy_configs` but *before* `get_wallpapers` and
  `normalize_hyprlock_wallpaper` — a half-finished install over folder colours.
  It warns and carries on instead. The `gsettings` calls beside it are
  deliberately **not** guarded: the schema comes from `gsettings-desktop-schemas`
  (pulled in by `gvfs`, in `PACMAN_PKGS`) and `dconf` is a hard dependency of
  gtk3/gtk4, so a failure there means something genuinely wrong.
- **`apply_gtk_theme()` ends with `thunar -q`.** GTK reads its stylesheet once at
  startup and thunar stays resident as a daemon after its last window closes, so
  on an *update* the new colours would not show until the next logout — which
  reads as the deploy having done nothing. It closes any open thunar windows.

`apply_gtk_theme()` also mirrors the theme into gsettings. `settings.ini` is only
read by GTK3 apps; `xdg-desktop-portal-gtk` and every GTK4/libadwaita app read
`org.gnome.desktop.interface` instead, so without it the portal file chooser
thunar opens is still stock Adwaita. Its values must be kept in step with
`gtk-3.0/settings.ini` by hand.

Two things `--pull` drags in, both in the repo `.gitignore`: `gtk-3.0/bookmarks`
(thunar's sidebar bookmarks — per-machine, and deliberately *not* shipped, so a
deploy's `cp -rf` leaves the live one alone) and `gtk-4.0/thumbnail.png`. The
`noctalia.css` these configs replaced is ignored for the same reason — deploying
`gtk.css` drops the `@import` that referenced it, but the orphan file stays on
disk until removed by hand.

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
  package name fails the whole transaction. `nvim` and `ttf-font-awesome` are not
  package names but resolve through `provides` (`neovim`, `woff2-font-awesome`) — they
  are fine, so don't "fix" them into a second entry for a package already listed.
- **A package install.sh itself depends on still has to be in `PACMAN_PKGS`.** `sddm`
  (which owns the theme directory `deploy_configs` copies into) and `avahi` (whose unit
  `first_install_extras` enables) are there for that reason alone, not because anything
  deployed uses them. So are `libnotify` and `wl-clipboard`, which the deployed scripts
  call directly and which otherwise arrive only as dependencies of thunar and cliphist.
- **The committed `hyprlock.conf` background is an absolute path**, so it names the
  `$HOME` of whichever machine last committed it. A first install preserves nothing, so
  on another username that path does not resolve and the lock screen has no background.
  `normalize_hyprlock_wallpaper()` re-points it under this machine's `$HOME` — same
  filename if it is there, otherwise any wallpaper — and does nothing when the committed
  path already resolves. It runs after `get_wallpapers`, so the images exist to point at,
  and rewrites the line with `sed` rather than calling `wallpaper-set.sh`, which needs
  the `awww` daemon up. During an install it is not.
- `*.sh` under any deployed `<app>/scripts/` is made executable by a `find` sweep — new
  scripts need no per-file `chmod`. (Several are committed mode 644, hence the sweep.)
- **A retired *daemon* needs more than a retired config.** `ORPHANS` deletes files;
  it does not stop a process or close a D-Bus activation path. `retire_swaync()` is the
  worked example — see **Notifications (quickshell)**.
- **`reload_session()` is what makes a deploy take effect.** Hyprland parses its config
  at startup and quickshell parses its QML once, so without it new keybinds and a new bar
  wait for the next logout — which reads as the deploy having done nothing, and is exactly
  how a changed `SUPER+SPACE` gets reported as broken. It runs `hyprctl reload`, then
  kills and re-`setsid`s quickshell — unconditionally, so exactly one bar is left however
  the reload treated `exec-once`. Every call is `|| true`: a cosmetic reload must not
  abort a finished deploy under `set -e`. It is the **last** step in `main()`, so the bar
  comes up reading everything the earlier steps wrote — including the icon theme
  `apply_gtk_theme` puts in gsettings, which is how `AppLauncher` resolves app icons on a
  machine that has never had one set. With Hyprland not running (installing from a TTY) it
  says so and does nothing.
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
lookup notes and deliberately stay manual. `README.md` is the human-facing half of this
file — install, `--pull`, the keybinds and the directory layout. Keep the two in step;
the internals (the preserve mechanism, the bar modules, the traps) live here, not there.
