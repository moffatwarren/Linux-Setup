import Quickshell
import Quickshell.Io
import QtQuick

// Generic wrapper around the shell helper scripts, which already
// print waybar-style JSON: {"text":…,"alt":…,"class":…}
// Used for tailscale.sh and pia.sh so their polling logic is not duplicated.
//
// It only parses and polls; the two subclasses both draw a fixed two- or
// three-letter label coloured by `rawAlt`, so nothing here composes a label
// beyond the script's own text.
Pill {
    id: root

    property string command: ""
    property int intervalMs: 3000
    property string clickCommand: ""
    property string doubleClickCommand: ""
    property string rightClickCommand: ""

    // The script's "text" and "alt" fields, kept separate: "alt" is the state
    // (connected/stopped/…) and "text" is whatever detail the script reports.
    property string rawText: ""
    property string rawAlt: ""

    label: rawText

    function run(cmd) {
        if (cmd.length > 0) Quickshell.execDetached(["bash", "-lc", cmd]);
    }

    onClicked: run(clickCommand)
    // A toggle takes several seconds to settle (PIA especially), so poll
    // quickly for a short while afterwards instead of waiting for the next
    // slow tick -- otherwise the click looks like it did nothing.
    //
    // Exposed as a function because a subclass cannot reach `fastPoll`: QML ids
    // are scoped to the file that declares them, so a derived component sees
    // this file's properties but none of its ids. TailscalePill needs it for a
    // toggle driven from inside its menu rather than from a click on the pill.
    property int fastTicks: 0
    function pollFast() {
        fastTicks = 0;
        fastPoll.running = true;
    }
    onDoubleClicked: {
        run(doubleClickCommand);
        pollFast();
    }

    Timer {
        id: fastPoll
        interval: 1000
        repeat: true
        running: false
        onTriggered: {
            if (!proc.running) proc.running = true;
            if (++root.fastTicks >= 15) {
                running = false;
                root.fastTicks = 0;
            }
        }
    }
    onRightClicked: run(rightClickCommand)

    Process {
        id: proc
        command: ["bash", "-lc", root.command]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (raw.length === 0) {
                    root.rawText = "";
                    root.rawAlt = "";
                    return;
                }
                // tailscale.sh joins its peer list with raw carriage returns,
                // which are illegal inside a JSON string and make JSON.parse
                // throw -- which used to blank the module the moment tailscale
                // came up. Escape any control characters before parsing.
                const safe = raw.replace(/[\u0000-\u001F]/g, c =>
                    "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0"));
                try {
                    const j = JSON.parse(safe);
                    root.rawAlt = j.alt !== undefined ? String(j.alt) : "";
                    root.rawText = j.text !== undefined ? String(j.text) : "";
                } catch (e) {
                    // Keep the last good value rather than making the pill vanish.
                    console.warn("ScriptPill: unparseable output from " + root.command + ": " + e);
                }
            }
        }
    }

    Timer {
        id: refresh
        interval: root.intervalMs
        running: root.command.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!proc.running) proc.running = true
    }
}
