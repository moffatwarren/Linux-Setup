import Quickshell
import Quickshell.Io
import QtQuick

// waybar: "custom/tailscale" -- format was
//   " Tailscale: {icon} | Exit-node: {text}"
// where {icon} is the alt-mapped connected/stopped state and {text} is the
// exit node name (or "no"). tailscale.sh is reused unchanged for the status.
//
// The peer list comes from `tailscale status --json` directly rather than from
// the script's tooltip, which wraps hostnames in pango markup and joins them
// with carriage returns.
ScriptPill {
    id: root

    readonly property bool connected: rawAlt === "connected"

    command: "~/.config/waybar/scripts/tailscale.sh --status"
    altText: ({ "connected": "on", "stopped": "off" })
    altColors: ({ "connected": Theme.green, "stopped": Theme.red })
    doubleClickCommand: "~/.config/waybar/scripts/tailscale.sh --toggle"
    rightClickCommand: "~/.config/waybar/scripts/tailscale.sh --getFile"

    label: {
        if (iconText.length === 0) return "";
        const state = stateColor.length > 0
            ? '<font color="' + stateColor + '">' + iconText + '</font>'
            : iconText;
        const base = " Tailscale: " + state;
        if (!connected) return base;
        return base + " | Exit-node: " + (rawText.length > 0 ? rawText : "no");
    }

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
        requested: root.hovered && root.connected
        title: "Tailscale peers"
        emptyText: "No peers"
        rows: root.peers.map(p => ({
            text: p.name + (p.exitNode ? "  (exit node)" : ""),
            detail: p.online ? "online" : "offline",
            accent: p.online ? Theme.green : Theme.overlay0
        }))
    }
}
