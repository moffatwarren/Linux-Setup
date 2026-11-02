#!/usr/bin/env bash
# Tries the aquarium lock on the running session:  lock-test.sh [seconds, default 60]
#
# Three nets under it. The lock unlocks itself when the time is up. A lock that has hung,
# and so can never reach that timer, is killed 15 seconds after it. And if the process
# ends for any reason without unlocking, hyprlock takes over so there is still a password
# prompt. That last one is why the restore option has to be on: Hyprland refuses a new
# locker while a dead one still holds the session, and the refusal would leave nothing to
# type into. So this will not start unless Hyprland confirms the option took.
set -u

dir=$(cd "$(dirname "$0")" && pwd)
seconds=${1:-60}

hyprctl -q eval 'hl.config({ misc = { allow_session_lock_restore = true } })'
if ! hyprctl getoption misc:allow_session_lock_restore | grep -q 'bool: true'; then
    echo "misc:allow_session_lock_restore is not on, so not locking." >&2
    exit 1
fi

AQUARIUM_TEST_SECONDS=$seconds timeout -s KILL "$((seconds + 15))" qs -p "$dir/lock-test.qml"
status=$?

if [ "$status" -ne 0 ]; then
    echo "The lock exited with status $status without unlocking; starting hyprlock." >&2
    hyprlock
fi
exit "$status"
