import Quickshell
import Quickshell.Io
import QtQuick

// Just the letters "TS", green when tailscale is up and the bar's normal text
// colour when it is not -- everything else moved into the hover panel, so the
// module costs two characters of bar rather than the waybar-era
// " Tailscale: on | Exit-node: …".
//
// tailscale.sh is reused unchanged for the state and the exit node. The peer
// list comes from `tailscale status --json` directly rather than from the
// script's tooltip, which wraps hostnames in pango markup and joins them with
// carriage returns.
ScriptPill {
    id: root

    readonly property bool connected: rawAlt === "connected"
    // tailscale.sh prints the literal string "no" when nothing is routing.
    readonly property string exitNode:
        connected && rawText.length > 0 && rawText !== "no" ? rawText : ""

    command: "~/.config/hypr/scripts/tailscale.sh --status"
    doubleClickCommand: "~/.config/hypr/scripts/tailscale.sh --toggle"
    rightClickCommand: "~/.config/hypr/scripts/tailscale.sh --getFile"

    // Hidden until the first poll lands: Pill drops a module with no label.
    label: rawAlt.length > 0 ? "TS" : ""
    labelColor: connected ? Theme.green : Theme.text

    property var peers: []

    Process {
        id: peerProc
        command: ["bash", "-lc", "tailscale status --json 2>/dev/null || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                if (raw.length === 0) {
                    root.peers = [];
                    return;
                }
                try {
                    const j = JSON.parse(raw);
                    const out = [];
                    for (const key in (j.Peer || {})) {
                        const p = j.Peer[key];
                        out.push({
                            name: String(p.DNSName || "").split(".")[0],
                            online: !!p.Online,
                            exitNode: !!p.ExitNode
                        });
                    }
                    // Online first, then alphabetical.
                    out.sort((a, b) => a.online !== b.online
                        ? (a.online ? -1 : 1)
                        : a.name.localeCompare(b.name));
                    root.peers = out;
                } catch (e) {
                    root.peers = [];
                }
            }
        }
    }

    // Only ask tailscale for peers while it is actually up.
    Timer {
        interval: 10000
        running: root.connected
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!peerProc.running) peerProc.running = true
    }

    onConnectedChanged: if (!connected) peers = [];

    ListPopup {
        anchorItem: root
        requested: root.hovered
        title: "Tailscale"
        maxDetailWidth: 220
        rows: {
            if (!root.connected)
                return [{ text: "Status", detail: "Disconnected", accent: Theme.red }];
            const on = [{ text: "Status", detail: "Connected", accent: Theme.green }];
            if (root.exitNode.length > 0)
                on.push({ text: "Exit node", detail: root.exitNode, accent: Theme.sapphire });
            for (const p of root.peers)
                on.push({
                    text: p.name + (p.exitNode ? "  (exit node)" : ""),
                    detail: p.online ? "online" : "offline",
                    accent: p.online ? Theme.green : Theme.overlay0
                });
            return on;
        }
    }
}
