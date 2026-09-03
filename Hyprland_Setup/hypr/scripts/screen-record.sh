#!/usr/bin/env bash
#
# Region screen recording, bound to SUPER+CTRL+S in hypr/modules/binds.lua.
# One key starts and stops it: --toggle picks a region with slurp and starts
# wf-recorder, or stops the recording already running.
#
#   --toggle        record a region (video only)
#   --toggle-audio  the same, plus the default audio input
#   --stop          stop, if recording
#   --status        print the state file, or an idle object
#
# The bar's RecorderPill reads the state file rather than polling this script;
# see RecorderService.qml.

set -euo pipefail

STATE="${XDG_RUNTIME_DIR:-/tmp}/screen-recording.json"
OUTDIR="$HOME/Videos/recordings"

# --- state ------------------------------------------------------------------
# The pill is driven by this file, so every path that changes what is happening
# has to write it and then poke the bar. Writing "recording: false" rather than
# deleting the file keeps the inotify watch in RecorderService valid.

write_state() {
  local recording=$1 pid=${2:-0} file=${3:-} started=${4:-0}
  printf '{"recording":%s,"pid":%s,"file":"%s","started":%s}\n' \
    "$recording" "$pid" "$file" "$started" > "$STATE"
  # The bar re-reads on this rather than on a timer. `|| true` because a
  # recording must not fail just because the bar happens to be restarting.
  qs ipc call recorder refresh >/dev/null 2>&1 || true
}

read_field() {
  [ -f "$STATE" ] || return 1
  sed -n "s/.*\"$1\":\"\?\([^,\"}]*\)\"\?.*/\1/p" "$STATE"
}

# Recording, as far as the state file is concerned AND with a live process
# behind it. The second half is what self-heals a state file left saying
# "recording" by a wf-recorder that was killed along with its supervisor.
is_recording() {
  local recording pid
  recording=$(read_field recording 2>/dev/null || echo false)
  [ "$recording" = "true" ] || return 1
  pid=$(read_field pid 2>/dev/null || echo 0)
  [ "$pid" -gt 0 ] 2>/dev/null || return 1
  kill -0 "$pid" 2>/dev/null
}

# --- actions ----------------------------------------------------------------

start() {
  local with_audio=$1 geometry file

  # One region select at a time. A second press while slurp is already on
  # screen would put two selection overlays up fighting over the pointer,
  # and neither of them has drawn anything to say why.
  if pgrep -x slurp >/dev/null 2>&1; then
    exit 0
  fi

  # slurp exits non-zero when the selection is cancelled with Escape, which is
  # a normal way to change your mind -- not an error worth a notification.
  if ! geometry=$(slurp -d 2>/dev/null); then
    exit 0
  fi

  mkdir -p "$OUTDIR"
  file="$OUTDIR/$(date +%Y-%m-%d_%H-%M-%S).mp4"

  # Detached, because the keybind's own process goes away the moment Hyprland
  # has spawned it -- and wf-recorder has to outlive it. --supervise runs
  # wf-recorder in the FOREGROUND so it has a parent to notice it exiting,
  # however it exits: our --stop, a crash, or a kill from elsewhere.
  setsid -f "$0" --supervise "$geometry" "$file" "$with_audio" >/dev/null 2>&1
}

supervise() {
  local geometry=$1 file=$2 with_audio=$3
  local args=(-g "$geometry" -f "$file")
  if [ "$with_audio" = "audio" ]; then args+=(--audio); fi

  wf-recorder "${args[@]}" >/dev/null 2>&1 &
  local pid=$!

  write_state true "$pid" "$file" "$(date +%s)"

  # Blocks until wf-recorder is done, whatever ended it.
  wait "$pid" 2>/dev/null || true
  write_state false

  if [ -s "$file" ]; then
    # The path in the clipboard is the useful half: it goes straight into a
    # chat window or an mpv command without opening a file manager.
    printf '%s' "$file" | wl-copy
    notify-send -a "screen-record" -u low \
      "Recording saved" "${file/#$HOME/\~}  —  path copied to clipboard"
  else
    rm -f "$file"
    notify-send -a "screen-record" -u critical \
      "Recording failed" "wf-recorder produced no output"
  fi
}

stop() {
  local pid
  pid=$(read_field pid 2>/dev/null || echo 0)
  # SIGINT, not SIGTERM: wf-recorder finalises the container on an interrupt
  # and a SIGTERM leaves an unplayable file. The supervisor writes the idle
  # state once it sees the process go.
  [ "$pid" -gt 0 ] 2>/dev/null && kill -INT "$pid" 2>/dev/null || true
}

case "${1:-}" in
  --toggle)
    if is_recording; then stop; else start noaudio; fi
    ;;
  --toggle-audio)
    if is_recording; then stop; else start audio; fi
    ;;
  --stop)
    # `|| true` so a --stop with nothing running is a no-op, not an exit 1
    # that set -e would turn into a failed keybind.
    is_recording && stop || true
    ;;
  --supervise)
    supervise "$2" "$3" "${4:-}"
    ;;
  --status)
    if is_recording; then
      cat "$STATE"
    else
      echo '{"recording":false,"pid":0,"file":"","started":0}'
    fi
    ;;
  *)
    echo "Usage: $0 {--toggle|--toggle-audio|--stop|--status}" >&2
    exit 1
    ;;
esac
