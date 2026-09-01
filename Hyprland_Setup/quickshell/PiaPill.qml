import Quickshell
import Quickshell.Io
import QtQuick

// waybar: "custom/pia". pia.sh is reused unchanged for the state and the label;
// the hover panel adds where the tunnel actually exits, which pia.sh's own
// tooltip did not cover.
//
// `piactl get region` reports the *selected* region, which is usually "auto",
// so the public IP is what actually says where you are exiting.
ScriptPill {
    id: root

    readonly property bool connected: rawAlt === "connected"

    command: "~/.config/hypr/scripts/pia.sh --status"
    prefix: "\udb80\udda7 PIA: "
    doubleClickCommand: "~/.config/hypr/scripts/pia.sh --toggle"
    altColors: ({
        "connected":     Theme.green,
        "connecting":    Theme.yellow,
        "disconnecting": Theme.yellow,
        "disconnected":  Theme.red,
        "error":         Theme.red
    })

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
            if (!root.connected) {
                const off = [{ text: "Status", detail: "Not connected", accent: Theme.red }];
                if (root.pubIp.length > 0 && root.pubIp !== "Unknown")
                    off.push({ text: "Public IP", detail: root.pubIp });
                return off;
            }
            const on = [{ text: "Status", detail: "Connected", accent: Theme.green }];
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
