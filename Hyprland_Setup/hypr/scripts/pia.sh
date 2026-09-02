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
  *)
    echo "Usage: $0 {--status|--toggle|--service|--start-service}"
    exit 1
    ;;
esac
