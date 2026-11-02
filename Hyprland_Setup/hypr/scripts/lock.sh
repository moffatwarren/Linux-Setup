#!/usr/bin/env bash
# The one way this desktop locks. hypridle, SUPER+L, SUPER+SHIFT+L and the power menu
# all come through here, so these rules cannot differ between them.
#
#   lock.sh            lock
#   lock.sh --suspend  lock, then suspend once the lock is really up
#
# The lock is the aquarium (~/.config/aquarium). hyprlock is the net under it: if the
# aquarium cannot lock in time, or dies without unlocking, hyprlock takes the session.
# A lock command that quietly fails leaves the desktop open, so every path out of here
# either has a lock up or has handed over to one.
set -u

want_suspend=false
[ "${1:-}" = "--suspend" ] && want_suspend=true

qml=${AQUARIUM_LOCK_QML:-$HOME/.config/aquarium/lock.qml}
run=${XDG_RUNTIME_DIR:-/tmp}
ready=$run/aquarium-lock-${WAYLAND_DISPLAY:-wayland}.ready
guard=$run/aquarium-lock-${WAYLAND_DISPLAY:-wayland}.guard

# How long the aquarium gets to lock. logind only holds a suspend for hypridle for 5 s
# (InhibitDelayMaxUSec), and hyprlock has to fit in what is left if this runs out.
limit_ms=3000

now_ms() { date +%s%3N; }

# hyprlock writes no marker to wait on, so this is the old fixed guess, for this path only.
fallback() {
    hyprlock 9>&- &
    local pid=$!
    if $want_suspend; then
        sleep 0.5
        systemctl suspend 9>&-
    fi
    wait "$pid"
    # Said afterwards, because nothing can be shown over a lock. The bar owns
    # notifications, so this is still waiting in the centre if it is missed.
    notify-send -u critical "Aquarium lock failed" \
        "$1, so hyprlock took over. See the newest log under \$XDG_RUNTIME_DIR/quickshell/by-id." 9>&-
}

wait_until_ready() {
    local start
    start=$(now_ms)
    until [ -e "$ready" ]; do
        [ -n "${1:-}" ] && ! kill -0 "$1" 2>/dev/null && return 1
        [ $(($(now_ms) - start)) -ge "$limit_ms" ] && return 1
        sleep 0.05
    done
}

# Only one lock at a time. Hyprland will not enforce it, because the restore option the
# fallback depends on also lets a second locker take over from a live one, and an older
# lock can then release the session out from under the newer one.
#
# This process alone holds the guard (9>&- on everything it starts). If something
# long-lived inherited it, the guard could outlast the lock and every later lock would
# exit here without locking, which is the one failure that must not be possible.
exec 9>"$guard"
if ! flock -n 9; then
    if $want_suspend; then
        wait_until_ready
        systemctl suspend 9>&-
    fi
    exit 0
fi

rm -f "$ready"
AQUARIUM_LOCK_READY=$ready qs -p "$qml" >/dev/null 2>&1 9>&- &
pid=$!

if ! wait_until_ready "$pid"; then
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    fallback "It did not lock within $limit_ms ms"
    exit 0
fi

$want_suspend && systemctl suspend 9>&-

wait "$pid"
status=$?
rm -f "$ready"

if [ "$status" -ne 0 ]; then
    fallback "It exited with status $status without unlocking"
fi
exit 0
