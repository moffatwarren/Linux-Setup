#!/usr/bin/env bash

# Private Internet Access (PIA) VPN status for the bar, and connect/disconnect.
# Written for waybar originally; PiaPill.qml now drives it, and still parses the
# waybar-style JSON --status prints.

PIACTL="/usr/local/bin/piactl"
if ! command -v piactl &> /dev/null; then
  if [ -f "/usr/local/bin/piactl" ]; then
    PIACTL="/usr/local/bin/piactl"
  elif [ -f "/usr/bin/piactl" ]; then
    PIACTL="/usr/bin/piactl"
  else
    PIACTL="piactl"
  fi
fi

# The systemd unit the PIA installer ships. The pill asks about it because
# piactl talks to this daemon: with it stopped, every `piactl get` fails and the
# module can only report "error", which says nothing about why.
PIA_SERVICE="piavpn.service"

pia_status() {
  $PIACTL get connectionstate
}

toggle_status() {
  STATE=$(pia_status)
  if [ "$STATE" = "Connected" ] || [ "$STATE" = "Connecting" ] || [ "$STATE" = "Reconnecting" ]; then
    $PIACTL disconnect
  else
    $PIACTL connect
  fi
}

# piactl only talks to the daemon; it cannot bring up a tunnel on its own.
# `piactl connect` fails outright unless the GUI client is running or background
# mode is enabled (`piactl background enable`) -- see `piactl --help`. That is a
# silent dead button in a menu, so every failure is reported. The hint is only
# attached to a connect, since that is the one that has this precondition.
report_failure() {
  local action="$1" err="$2" hint="${3:-}"
  local body="${err:-piactl gave no reason.}"
  [ -n "$hint" ] && body="${body}"$'\n'"${hint}"
  # No -i, for the reason BatteryWatcher sends none: a themed *-symbolic icon
  # has a near-black fill baked into the SVG and is invisible on the toast's
  # `base` card. With no icon NotificationToasts draws its own glyph in the
  # urgency accent -- a red warning triangle, which is what this should be.
  notify-send -u critical "PIA: ${action} failed" "$body"
}

case "$1" in
  --status)
    STATE=$(pia_status)
    # If the daemon isn't running or errors out
    if [ $? -ne 0 ] || [ -z "$STATE" ]; then
      echo '{"text":"Error","class":"error","alt":"error","tooltip":"PIA daemon not responding"}'
      exit 1
    fi

    case "$STATE" in
      Connected)
        VPN_IP=$($PIACTL get vpnip)
        REGION=$($PIACTL get region)
        echo "{\"text\":\"Connected\",\"class\":\"connected\",\"alt\":\"connected\",\"tooltip\":\"PIA VPN: Connected\nRegion: ${REGION}\nVPN IP: ${VPN_IP}\"}"
        ;;
      Connecting|Reconnecting)
        echo "{\"text\":\"Connecting\",\"class\":\"connecting\",\"alt\":\"connecting\",\"tooltip\":\"PIA VPN: Connecting...\"}"
        ;;
      Disconnecting)
        echo "{\"text\":\"Disconnecting\",\"class\":\"disconnecting\",\"alt\":\"disconnecting\",\"tooltip\":\"PIA VPN: Disconnecting...\"}"
        ;;
      Disconnected)
        echo '{"text":"Disconnected","class":"disconnected","alt":"disconnected","tooltip":"PIA VPN: Disconnected"}'
        ;;
      *)
        echo "{\"text\":\"$STATE\",\"class\":\"unknown\",\"alt\":\"unknown\",\"tooltip\":\"PIA VPN State: $STATE\"}"
        ;;
    esac
    ;;
  --toggle)
    toggle_status
    ;;
  --service)
    # A unit that does not exist reports "inactive" too (verified: prints
    # "inactive", exits 4), so is-active alone cannot tell "PIA is installed and
    # stopped" from "PIA was never installed". PIA is an optional extra in
    # install.sh, so the second case is the normal state of a fresh machine --
    # and the bar must not offer to start something that is not there.
    if ! systemctl cat "$PIA_SERVICE" >/dev/null 2>&1; then
      echo "absent"
      exit 0
    fi
    # `is-active` exits non-zero for anything but "active", which is not a
    # failure here -- the word it prints is the whole answer.
    systemctl is-active "$PIA_SERVICE" 2>/dev/null || true
    ;;
  --start-service)
    # Run from a terminal window (PiaPill's right-click), because starting a
    # system unit needs a password and this session has no polkit agent to ask
    # for one. Held open on failure so the error is readable.
    if ! systemctl cat "$PIA_SERVICE" >/dev/null 2>&1; then
      echo "${PIA_SERVICE} is not installed on this machine."
      echo "Install PIA with: paru -S piavpn-bin"
      echo
      read -r -n1 -p "Press any key to close."
      exit 1
    fi
    if ! sudo systemctl start "$PIA_SERVICE"; then
      echo
      read -r -n1 -p "Failed to start ${PIA_SERVICE}. Press any key to close."
      exit 1
    fi
    ;;
  --connect)
    if ! ERR=$($PIACTL connect 2>&1); then
      report_failure "Connect" "$ERR" \
        "piactl needs the PIA client running, or background mode: piactl background enable"
      exit 1
    fi
    ;;
  --disconnect)
    if ! ERR=$($PIACTL disconnect 2>&1); then
      report_failure "Disconnect" "$ERR"
      exit 1
    fi
    ;;
  --regions)
    # Raw region ids, one per line, "auto" first -- exactly as piactl prints
    # them. The menu turns `us-salt-lake-city` into `US Salt Lake City`, the
    # way the weather and stats modules format their scripts' raw numbers.
    # Empty output (daemon down) is a normal answer, not an error.
    $PIACTL get regions 2>/dev/null || true
    ;;
  --set-region)
    # Selecting a region does not move a live tunnel: `piactl connect` doubles
    # as "reconnect to apply new settings" (`piactl --help`), so it is run
    # either way -- to apply the change when connected, and because picking a
    # place to connect to means you want to be connected to it when not.
    if [ -z "${2:-}" ]; then
      echo "Usage: $0 --set-region <region-id>" >&2
      exit 1
    fi
    if ! ERR=$($PIACTL set region "$2" 2>&1); then
      report_failure "Region" "$ERR"
      exit 1
    fi
    if ! ERR=$($PIACTL connect 2>&1); then
      report_failure "Connect" "$ERR" \
        "piactl needs the PIA client running, or background mode: piactl background enable"
      exit 1
    fi
    ;;
  --open-client)
    # The GUI, for everything this menu deliberately does not carry: the full
    # region list, settings, the account. Launched the way the shipped
    # /usr/share/applications/piavpn.desktop does -- XDG_SESSION_TYPE=X11 and
    # from its own directory. The client is a Qt app that expects X11, so it
    # runs under XWayland; dropping that env is how it fails to start with
    # nothing on screen to say why.
    CLIENT="/opt/piavpn/bin/pia-client"
    if [ ! -x "$CLIENT" ]; then
      notify-send -u critical "PIA" "PIA client not found at ${CLIENT}."
      exit 1
    fi
    cd "$(dirname "$CLIENT")" || exit 1
    XDG_SESSION_TYPE=X11 setsid -f "$CLIENT" >/dev/null 2>&1
    ;;
  *)
    echo "Usage: $0 {--status|--toggle|--connect|--disconnect|--regions|--set-region <id>|--service|--start-service|--open-client}"
    exit 1
    ;;
esac
