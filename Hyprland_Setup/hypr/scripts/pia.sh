#!/usr/bin/env bash

# Helper script for Waybar to display Private Internet Access (PIA) VPN status
# and toggle connection on double-click.

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
  *)
    echo "Usage: $0 {--status|--toggle}"
    exit 1
    ;;
esac
