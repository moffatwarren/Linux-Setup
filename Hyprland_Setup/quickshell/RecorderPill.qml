import Quickshell
import QtQuick

// Shown only while a screen recording is running (SUPER+CTRL+S): a red dot
// and the elapsed time, click to stop. Hidden the rest of the time, which is
// Pill's own behaviour on an empty label.
//
// Deliberately not blinking. A pulsing record dot is the convention, but
// nothing else on this bar animates, and a blink in the corner of the eye for
// the length of a screencast is worse than a steady red.
Pill {
    id: root

    // Ticked by the timer below rather than read from the clock on each
    // binding pass, so the elapsed text updates once a second instead of
    // whenever something else happens to invalidate it.
    property int now: 0

    readonly property int elapsed: RecorderService.started > 0
                                   ? Math.max(0, root.now - RecorderService.started) : 0

    function clock(seconds) {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        const s = seconds % 60;
        const mm = String(m).padStart(h > 0 ? 2 : 1, "0");
        return (h > 0 ? h + ":" : "") + mm + ":" + String(s).padStart(2, "0");
    }

    // \uf111 (fa-circle), escaped rather than pasted -- see CLAUDE.md.
    label: RecorderService.recording ? "\uf111 " + root.clock(root.elapsed) : ""
    labelColor: Theme.red

    onClicked: RecorderService.stop()

    Timer {
        interval: 1000
        repeat: true
        running: RecorderService.recording
        triggeredOnStart: true
        onTriggered: root.now = Math.floor(Date.now() / 1000)
    }

    ListPopup {
        anchorItem: root
        requested: root.hovered && RecorderService.recording
        title: "Recording"
        rows: [
            { text: "Elapsed", detail: root.clock(root.elapsed), accent: Theme.red },
            { text: "File", detail: RecorderService.file.replace(/^.*\//, "") },
            { text: "", detail: "click to stop", accent: Theme.subtext0 }
        ]
        // A recording's filename is a timestamp, but the popup should not
        // stretch across the screen if that ever changes.
        maxDetailWidth: 280
    }
}
