pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Pending package updates. hypr/scripts/updates.sh is the whole backend; this
// only polls it, parses it and holds the answer.
//
// A singleton for the reason RecorderService and AudioService are: there is one
// Bar per monitor and so one UpdatePill each, they all have to agree, and a
// per-monitor poll would run the check once per screen. It is also what gives
// `qs ipc call updates refresh` something to talk to -- see shell.qml.
Singleton {
    id: root

    readonly property string scriptPath:
        Quickshell.env("HOME") + "/.config/hypr/scripts/updates.sh"

    // [{ name, old, new }], straight from the script.
    property var repo: []
    property var aur: []
    // Unix seconds of the last real sync, from the script's own `updated`
    // field rather than from a clock here: almost every poll is served from the
    // six-hour cache, so a timestamp taken when the bar ran `cat` would report
    // when it last looked rather than when the data arrived. It also survives a
    // bar restart, which every deploy performs.
    property double updatedAt: 0
    // False until the first answer of the session. The script prints nothing
    // rather than guessing when it cannot tell, so until something parses there
    // is no honest state to draw and the pill stays out of the bar -- "up to
    // date" and "the check has never worked" must not look the same.
    property bool known: false
    // Only set by a click, never by the background poll: a spinner that appears
    // on its own every six hours is noise, and the timer's tick is usually a
    // `cat` anyway.
    property bool refreshing: false

    readonly property int count: repo.length + aur.length

    function check(force) {
        if (proc.running) return;
        proc.mode = force ? "--force" : "";
        if (force) root.refreshing = true;
        proc.running = true;
    }

    // The cheap half: no network, just drop what has since been installed. See
    // updates.sh for why one `pacman -Q` is enough.
    function revalidate() {
        if (proc.running) return;
        proc.mode = "--revalidate";
        proc.running = true;
    }

    Process {
        id: proc

        // Bound into the command, so it must not be rewritten under a running
        // process -- every caller above guards on `running` first. Same rule as
        // WeatherPill's `force`.
        property string mode: ""

        command: ["bash", "-lc", root.scriptPath + (mode.length > 0 ? " " + mode : "")]
        onExited: root.refreshing = false

        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                // Nothing printed means the script could not tell (no network,
                // no cache). Keep the last good reading.
                if (raw.length === 0) return;
                try {
                    const j = JSON.parse(raw);
                    root.repo = j.repo !== undefined ? j.repo : [];
                    root.aur = j.aur !== undefined ? j.aur : [];
                    root.updatedAt = j.updated !== undefined ? Number(j.updated) : 0;
                    root.known = true;
                } catch (e) {
                    console.warn("UpdateService: unparseable output: " + e);
                }
            }
        }
    }

    // Six hours, matching the script's own cache, so a tick that lands on a
    // warm cache is a `cat` rather than a database sync. Arch's repos move a
    // few times a day; polling harder would be four network syncs an hour to
    // learn nothing.
    Timer {
        interval: 6 * 60 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.check(false)
    }

    // The asymmetry is deliberate. A pill saying "up to date" can only go
    // wrong in the direction that needs a network sync to detect, which is what
    // the six-hourly timer is for. A pill showing a count goes wrong the moment
    // you run `paru -Syu` in a terminal -- and THAT is answerable locally for
    // free, so it is worth checking often. Only the stale direction is cheap,
    // so only the stale direction is polled.
    Timer {
        interval: 10 * 60 * 1000
        running: root.count > 0
        repeat: true
        onTriggered: root.revalidate()
    }
}
