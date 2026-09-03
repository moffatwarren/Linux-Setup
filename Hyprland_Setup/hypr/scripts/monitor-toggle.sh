#!/bin/bash
#
# SUPER+SHIFT+Z -- turn the laptop's built-in screen off, or back on.
#
# There is no configured monitor name behind this. The built-in panel is the one
# on an *internal* connector, and Hyprland names monitors after the DRM
# connector they are on -- verified: /sys/class/drm/card1-DP-2 is the monitor
# Hyprland calls "DP-2". The kernel only ever uses eDP (every current laptop),
# LVDS (pre-2013) or DSI (tablets and a few ARM laptops) for a panel wired to
# the board, and never for anything you can plug in. So "is this the laptop
# screen" is answerable from the connector name alone, on any machine, with
# nothing to set up.
#
# This replaced `config.mainMonitor` in hypr/modules/config.lua, a hand-set name
# that install.sh had to carry across every deploy. It was also wrong: it said
# "DP-1" on a machine whose monitor is DP-2, so the key had been pointing at a
# disconnected connector with nothing to report it.
#
#   --toggle   (default) off if on, on if off        SUPER+SHIFT+Z
#   --off      only ever turns it off                 lid close
#   --on       only ever turns it on                  lid open, monitor.removed
#
# Deliberately silent. On a desktop, and on a laptop with nothing else plugged
# in, this key has nothing useful to do and says so by doing nothing -- a toast
# every time you fat-finger it would be worse than the no-op.

INTERNAL_RE='^(eDP|LVDS|DSI)'

# The connected internal panel, or nothing. Sorted so a machine with two (no
# such machine, but the glob permits it) picks the same one every run.
internal_panel() {
  local path name
  for path in /sys/class/drm/card*-*/status; do
    [ -e "$path" ] || continue
    name=${path%/status}
    name=${name##*/}
    name=${name#card*-}
    [[ "$name" =~ $INTERNAL_RE ]] || continue
    [ "$(cat "$path" 2>/dev/null)" = "connected" ] || continue
    printf '%s\n' "$name"
  done | sort | head -1
}

# Monitors Hyprland currently has enabled. A monitor that is connected but
# disabled is absent from this list -- which is how the state below is read,
# rather than by tracking a boolean in Lua that goes stale the moment anything
# changes a monitor by another route.
enabled_monitors() {
  hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null
}

# Validated before anything is probed, so a typo is reported on every machine
# rather than only on one that happens to have a panel to act on.
MODE="${1:---toggle}"
case "$MODE" in
  --toggle|--on|--off) ;;
  *) echo "usage: ${0##*/} [--toggle|--on|--off]" >&2; exit 1 ;;
esac

PANEL=$(internal_panel)
# No internal panel: a desktop. Nothing to toggle.
[ -n "$PANEL" ] || exit 0

ENABLED=$(enabled_monitors)
# hyprctl is unreachable (Hyprland not running); nothing to do either.
[ -n "$ENABLED" ] || exit 0

panel_is_on() { printf '%s\n' "$ENABLED" | grep -Fxq -- "$PANEL"; }
other_monitor_on() { printf '%s\n' "$ENABLED" | grep -Fxvq -- "$PANEL"; }

panel_on()  { hyprctl keyword monitor "$PANEL,highrr,auto,1" >/dev/null 2>&1; }

# Never turn the panel off while it is the only thing showing. That is the whole
# "laptop with an external screen" condition, and it is the difference between a
# key that does nothing and a machine with every display disabled and no way to
# see the shortcut that undoes it. The lid shares it: with no second screen,
# closing the lid is logind's business (suspend), not ours.
panel_off() {
    other_monitor_on || return 0
    hyprctl keyword monitor "$PANEL,disable" >/dev/null 2>&1
}

case "$MODE" in
    --toggle) if panel_is_on; then panel_off; else panel_on; fi ;;
    # Turning it back on is deliberately NOT guarded on an external being
    # present: unplugging the external while the panel is off has to be
    # recoverable, and monitor.removed calls --on for exactly that.
    --on)     panel_is_on || panel_on ;;
    --off)    panel_is_on && panel_off ;;
esac

exit 0
