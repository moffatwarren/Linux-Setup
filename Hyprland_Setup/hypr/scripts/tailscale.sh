#!/usr/bin/env bash

tailscale_status() {
  return "$(tailscale status --json | jq -r '.BackendState | if . == "Running" then 0 else 1 end')"
}

toggle_status() {
  if tailscale_status; then
    tailscale down
  else
    tailscale up
  fi
  sleep 5
}

get_file() {
  tailscale file get ~/Downloads/
}

case $1 in
--status)
  # Printing nothing clears ScriptPill's rawAlt, and Pill hides a module with an
  # empty label. tailscale is an optional extra in install.sh, so a machine that
  # declined it would otherwise carry a TS pill stuck permanently at "off" --
  # the "stopped" branch below cannot tell "installed and down" from "not
  # installed", since `tailscale status` fails identically either way.
  if ! command -v tailscale >/dev/null 2>&1; then
    exit 0
  fi

  if tailscale_status; then
    T=${2:-"lightblue"}
    F=${3:-"red"}

    peers=$(tailscale status --json | jq -r --arg T "'$T'" --arg F "'$F'" '.Peer[]? | ("<span color=" + (if .Online then $T else $F end) + ">" + (.DNSName | split(".")[0]) + "</span>")' | tr '\n' '\r')
    exitnode=$(tailscale status --json | jq -r '.Peer[]? | select(.ExitNode == true).DNSName | split(".")[0]')

    if [ -z "$exitnode" ]; then
      echo "{\"text\":\"no\",\"class\":\"connected\",\"alt\":\"connected\", \"tooltip\": \"${peers}\"}"
    else
      echo "{\"text\":\"${exitnode}\",\"class\":\"connected\",\"alt\":\"connected\", \"tooltip\": \"${peers}\"}"
    fi

  else
    echo "{\"text\":\"\",\"class\":\"stopped\",\"alt\":\"stopped\", \"tooltip\": \"Tailscale not active.\"}"
  fi
  ;;
--toggle)
  toggle_status
  ;;
--getFile)
  get_file
  ;;
esac
