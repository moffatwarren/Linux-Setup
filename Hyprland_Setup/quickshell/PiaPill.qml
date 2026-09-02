import Quickshell
import Quickshell.Io
import QtQuick

// Just the letters "PIA", green when the tunnel is up and the bar's normal text
// colour otherwise -- the state word and the shield glyph moved out of the bar,
// since the hover panel already says the same thing in full.
//
// pia.sh drives the state, whether its daemon is even up, and starting that
// daemon; the hover panel adds where the tunnel actually exits, which pia.sh's
// own tooltip did not cover.
//
// `piactl get region` reports the *selected* region, which is usually "auto",
// so the public IP is what actually says where you are exiting.
ScriptPill {
    id: root

    readonly property bool connected: rawAlt === "connected"

    command: "~/.config/hypr/scripts/pia.sh --status"
    doubleClickCommand: "~/.config/hypr/scripts/pia.sh --toggle"

    // Hidden until the first poll lands: Pill drops a module with no label.
    label: rawAlt.length > 0 ? "PIA" : ""
    labelColor: connected ? Theme.green : Theme.text

    // `systemctl is-active piavpn.service`, via pia.sh so the unit name lives
    // with the rest of PIA's plumbing rather than in the QML.
    property string serviceState: ""
    readonly property bool serviceRunning: serviceState === "active"

    property string region: ""
    property string vpnIp: ""
    property string pubIp: ""
    property string protocol: ""
    // Resolved exit region when `region` is the useless "auto".
    property string actualRegion: ""

    // What to show on the Region row: the resolved region when PIA picked one
    // for us, the configured region otherwise.
    readonly property string regionLabel: {
        if (region === "auto")
            return actualRegion.length > 0 ? actualRegion + "  (auto)" : "auto";
        return region;
    }

    Process {
        id: serviceProc
        command: ["bash", "-lc", "~/.config/hypr/scripts/pia.sh --service"]
        stdout: StdioCollector {
            onStreamFinished: root.serviceState = text.trim()
        }
    }

    // Starting a system unit needs a password and this session runs no polkit
    // agent, so a terminal is the only place that prompt can be answered.
    // Offered only once a poll has actually reported the daemon down -- and not
    // at all while it is up, where a right-click has nothing to do.
    rightClickCommand: serviceState.length > 0 && !serviceRunning
        ? "kitty --class pia-start -e ~/.config/hypr/scripts/pia.sh --start-service"
        : ""

    // ScriptPill's own onRightClicked is what runs that; this one only starts
    // watching. Declaring a handler here does NOT replace the base component's
    // -- both fire -- so the command must not be run in both places.
    onRightClicked: if (rightClickCommand.length > 0) startPoll.restart()

    // The daemon takes a few seconds to come up and the password prompt is
    // untimed, so watch for a while rather than waiting on the 20 s tick.
    Timer {
        id: startPoll
        interval: 2000
        repeat: true
        running: false
        triggeredOnStart: true
        property int ticks: 0
        onRunningChanged: if (running) ticks = 0
        onTriggered: {
            root.refreshDetails();
            if (root.serviceRunning || ++ticks >= 45) running = false;
        }
    }

    Process {
        id: regionProc
        command: ["bash", "-lc", "~/.config/hypr/scripts/pia-region.sh"]
        stdout: StdioCollector {
            onStreamFinished: root.actualRegion = text.trim()
        }
    }

    Process {
        id: details
        command: ["bash", "-lc",
                  "piactl get region 2>/dev/null; piactl get vpnip 2>/dev/null; " +
                  "piactl get pubip 2>/dev/null; piactl get protocol 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n").map(x => x.trim());
                root.region   = l[0] !== undefined ? l[0] : "";
                root.vpnIp    = l[1] !== undefined ? l[1] : "";
                root.pubIp    = l[2] !== undefined ? l[2] : "";
                root.protocol = l[3] !== undefined ? l[3] : "";
            }
        }
    }

    function refreshDetails() {
        if (!details.running) details.running = true;
        if (!regionProc.running) regionProc.running = true;
        if (!serviceProc.running) serviceProc.running = true;
    }

    // Refresh on a slow tick, and immediately whenever the state flips or the
    // panel is about to be shown.
    Timer {
        interval: 20000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshDetails()
    }
    onConnectedChanged: { if (!connected) actualRegion = ""; refreshDetails(); }
    onHoveredChanged: if (hovered) refreshDetails()

    ListPopup {
        anchorItem: root
        requested: root.hovered
        title: "PIA VPN"
        rows: {
            // With the daemon down, piactl answers nothing and the connection
            // state below is meaningless -- so that is the whole panel.
            if (root.serviceState.length > 0 && !root.serviceRunning)
                return [
                    { text: "Service", detail: "Not running", accent: Theme.red },
                    { text: "", detail: "Right-click to start", accent: Theme.overlay0 }
                ];
            if (!root.connected) {
                const off = [
                    { text: "Service", detail: "Running", accent: Theme.green },
                    { text: "Status",  detail: "Not connected", accent: Theme.red }
                ];
                if (root.pubIp.length > 0 && root.pubIp !== "Unknown")
                    off.push({ text: "Public IP", detail: root.pubIp });
                return off;
            }
            const on = [
                { text: "Service", detail: "Running", accent: Theme.green },
                { text: "Status",  detail: "Connected", accent: Theme.green }
            ];
            if (root.regionLabel.length > 0) on.push({ text: "Region", detail: root.regionLabel });
            if (root.pubIp.length > 0 && root.pubIp !== "Unknown")
                on.push({ text: "Exit IP", detail: root.pubIp, accent: Theme.sapphire });
            if (root.vpnIp.length > 0 && root.vpnIp !== "Unknown")
                on.push({ text: "VPN IP",  detail: root.vpnIp });
            if (root.protocol.length > 0) on.push({ text: "Protocol", detail: root.protocol });
            return on;
        }
    }
}
