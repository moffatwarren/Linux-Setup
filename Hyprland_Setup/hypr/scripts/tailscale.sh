#!/usr/bin/env bash
#
# The tailscale module's backend (ScriptPill via TailscalePill.qml). Prints one
# waybar-style object: {"text":…,"class":…,"alt":…,"tooltip":…}
#
# `tailscale status --json` is asked ONCE per run and every field is derived
# from that one capture. It used to be called three times -- the BackendState
# test, the peer list and the exit node each ran their own -- which at the
# pill's poll interval was three daemon round trips a tick, for ever, to answer
# one question.

set -uo pipefail

# The stopped object, which is NOT the same answer as printing nothing:
# nothing clears ScriptPill's rawAlt and so takes the module out of the bar
# (what a machine with no tailscale installed gets), while this is the module
# present and reporting "down". `tailscale status` fails identically either
# way, so the difference has to be drawn here.
STOPPED='{"text":"","class":"stopped","alt":"stopped", "tooltip": "Tailscale not active."}'

status_json() {
  tailscale status --json 2>/dev/null
}

# Exit status, for toggle_status. The --status branch below does not use this:
# it has the capture already and testing BackendState inside its own jq is one
# fewer process than calling out here.
tailscale_running() {
  local state
  state=$(status_json | jq -r '.BackendState // empty' 2>/dev/null)
  [ "$state" = "Running" ]
}

toggle_status() {
  if tailscale_running; then
    tailscale down
  else
    tailscale up
  fi
  sleep 5
}

get_file() {
  tailscale file get ~/Downloads/
}

# Route through a peer, or stop routing through one when the target is empty.
# Targeted by Tailscale IP rather than hostname: a MagicDNS short name can be
# ambiguous across a tailnet, an IP cannot. `tailscale set` needs no sudo once
# this user is the operator (`tailscale set --operator=$USER`), which is also
# what `--toggle` already relies on. A failure goes out through notify-send for
# the reason pia.sh's do: a menu button that silently does nothing is the worst
# version of a failure.
set_exit_node() {
  local target="${1:-}" name="${2:-$1}" err
  if ! err=$(tailscale set --exit-node="$target" 2>&1); then
    if [ -n "$target" ]; then
      notify-send -u critical "Tailscale: exit node failed" "Could not route through ${name}: ${err}"
    else
      notify-send -u critical "Tailscale: exit node failed" "Could not stop using the exit node: ${err}"
    fi
    return 1
  fi
}

case "${1:-}" in
--status)
  # Not installed at all: print nothing, which hides the module. (The logo is
  # drawn rather than labelled, so an empty label is not what hides it --
  # TailscalePill binds hasContent to rawAlt.)
  command -v tailscale >/dev/null 2>&1 || exit 0

  STATUS=$(status_json)
  if [ -z "$STATUS" ]; then
    printf '%s\n' "$STOPPED"
    exit 0
  fi

  # One jq over the capture builds the whole object. The peer list is pango
  # markup joined with carriage returns, which is why ScriptPill escapes
  # control characters before JSON.parse; nothing in the bar reads `tooltip`
  # any more (TailscaleMenu gets its peers from its own `status --json`), so
  # this field is kept only because dropping it is a separate decision.
  jq -c --arg T "'${2:-lightblue}'" --arg F "'${3:-red}'" '
    if .BackendState == "Running" then
      { text:    ( [ .Peer[]? | select(.ExitNode == true) | (.DNSName | split(".")[0]) ] | first // "no" ),
        class:   "connected",
        alt:     "connected",
        tooltip: ( [ .Peer[]? | "<span color=" + (if .Online then $T else $F end) + ">"
                                + (.DNSName | split(".")[0]) + "</span>\r" ] | join("") ) }
    else
      { text: "", class: "stopped", alt: "stopped", tooltip: "Tailscale not active." }
    end
  ' <<<"$STATUS" 2>/dev/null || printf '%s\n' "$STOPPED"
  ;;
--toggle)
  toggle_status
  ;;
--getFile)
  get_file
  ;;
--exit-node)
  # --exit-node <ip> [name] uses a peer; --exit-node with no ip clears it.
  set_exit_node "${2:-}" "${3:-}"
  ;;
esac
