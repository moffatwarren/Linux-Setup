pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// State for the screen recorder bound to SUPER+CTRL+S. hypr/scripts/
// screen-record.sh is the whole backend; this only reads what it wrote.
//
// A FileView rather than a Process on a timer, for the reason NetworkPill
// samples /sys with one: an idle bar should spawn nothing. The script pokes
// `qs ipc call recorder refresh` every time the state changes, so even the
// file read only happens when something actually happened.
//
// A singleton because there is one bar per monitor, and every RecorderPill has
// to agree about whether a recording is running.
Singleton {
    id: root

    // Matches STATE in screen-record.sh. Under XDG_RUNTIME_DIR rather than
    // ~/.cache on purpose: /run/user/<uid> is wiped at logout, so a state file
    // orphaned by a crash cannot outlive the session and leave the bar
    // claiming to be recording forever.
    readonly property string statePath:
        (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/screen-recording.json"

    readonly property string scriptPath:
        Quickshell.env("HOME") + "/.config/hypr/scripts/screen-record.sh"

    property bool recording: false
    property string file: ""
    // Unix seconds, from the script -- not the time the bar noticed, so the
    // elapsed clock survives a bar restart mid-recording.
    property int started: 0

    function reload() { stateFile.reload(); }

    function stop() { Quickshell.execDetached([root.scriptPath, "--stop"]); }

    function toggle() { Quickshell.execDetached([root.scriptPath, "--toggle"]); }

    FileView {
        id: stateFile

        path: root.statePath
        preload: true
        // Absent until the first recording of the session, which is the normal
        // case rather than an error.
        printErrors: false
        // Backstop for the ipc poke: covers a state change that lands while
        // the bar is restarting.
        watchChanges: true

        onFileChanged: stateFile.reload()
        onLoadFailed: {
            root.recording = false;
            root.file = "";
            root.started = 0;
        }

        onLoaded: {
            try {
                const parsed = JSON.parse(stateFile.text());
                root.recording = parsed.recording === true;
                root.file = String(parsed.file ?? "");
                root.started = Number(parsed.started ?? 0);
            } catch (e) {
                // A half-written file on the next tick is not worth blanking a
                // running recording over; keep the last good state.
                console.warn("RecorderService: unparseable state file: " + e);
            }
        }
    }
}
