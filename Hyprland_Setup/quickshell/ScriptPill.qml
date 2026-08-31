import Quickshell
import Quickshell.Io
import QtQuick

// Generic wrapper around the shell helper scripts, which already
// print waybar-style JSON: {"text":…,"alt":…,"class":…}
// Used for tailscale.sh, pia.sh and weather.sh so their logic is not duplicated.
Pill {
    id: root

    property string command: ""
    property int intervalMs: 3000
    property string clickCommand: ""
    property string doubleClickCommand: ""
    property string rightClickCommand: ""
    // Maps the script's "alt" field to display text, like waybar's format-icons.
    property var altText: ({})
    // Maps the same "alt" field to a colour for the state word only, the way
    // waybar's CSS coloured #custom-pia by its class.
    property var altColors: ({})
    property string prefix: ""

    // j.text and the altText-mapped j.alt are kept separate so a subclass can
    // compose both (waybar's tailscale format shows state AND exit node).
    property string rawText: ""
    property string rawAlt: ""
    property string iconText: ""

    readonly property string stateColor: {
        const c = altColors[rawAlt];
        return c !== undefined ? String(c) : "";
    }

    richText: stateColor.length > 0

    label: {
        const shown = iconText.length > 0 ? iconText : rawText;
        if (shown.length === 0) return "";
        if (stateColor.length === 0) return prefix + shown;
        return prefix + '<font color="' + stateColor + '">' + shown + '</font>';
    }

    function run(cmd) {
        if (cmd.length > 0) Quickshell.execDetached(["bash", "-lc", cmd]);
    }

    onClicked: run(clickCommand)
    // A toggle takes several seconds to settle (PIA especially), so poll
    // quickly for a short while afterwards instead of waiting for the next
    // slow tick -- otherwise the click looks like it did nothing.
    property int fastTicks: 0
    onDoubleClicked: {
        run(doubleClickCommand);
        fastTicks = 0;
        fastPoll.running = true;
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
                    root.iconText = "";
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
                    const mapped = root.altText[root.rawAlt];
                    root.iconText = mapped !== undefined ? String(mapped) : "";
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
