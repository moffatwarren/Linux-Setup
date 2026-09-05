import Quickshell
import Quickshell.Io
import QtQuick

// The tailscale mark, green when tailscale is up and the bar's normal text
// colour when it is not -- everything else lives in TailscaleMenu, so the
// module costs one glyph of bar rather than the waybar-era
// " Tailscale: on | Exit-node: …".
//
// tailscale.sh is reused unchanged for the state and the exit node. The peer
// list comes from `tailscale status --json` directly rather than from the
// script's tooltip, which wraps hostnames in pango markup and joins them with
// carriage returns.
//
// **Left-click opens the menu**, as every other pill that owns one does.
// **Right-click toggles connect/disconnect**, running the same action as the
// Connect/Disconnect button inside the menu. `clickCommand`,
// `doubleClickCommand` and `rightClickCommand` are all unset and the base's
// handlers run `run("")`, which is a no-op.
ScriptPill {
    id: root

    readonly property bool connected: rawAlt === "connected"
    // tailscale.sh prints the literal string "no" when nothing is routing.
    readonly property string exitNode:
        connected && rawText.length > 0 && rawText !== "no" ? rawText : ""

    readonly property string toggleCommand: "~/.config/hypr/scripts/tailscale.sh --toggle"
    readonly property string getFileCommand: "~/.config/hypr/scripts/tailscale.sh --getFile"

    command: "~/.config/hypr/scripts/tailscale.sh --status"

    // The logo is drawn rather than labelled, so `hasContent` carries what an
    // empty label used to: hidden until the first poll lands.
    label: ""
    hasContent: rawAlt.length > 0
    contentWidth: logo.implicitWidth
    labelColor: connected ? Theme.green : Theme.text

    // Nerd Fonts ships no tailscale glyph and nothing on this system installs
    // the artwork, so the mark is drawn: the 3x3 dot grid from tailscale's own
    // favicon, in which the middle row plus the dot below it form the "t" at
    // full opacity and the remaining five sit behind it at 0.4. Both take
    // `labelColor`, so the module is still one colour saying one thing.
    //
    // The favicon's dots are radius 3 on a 9 pitch, i.e. a gap of half a dot;
    // keep that ratio if the size is ever changed, or the grid stops reading
    // as the logo and starts reading as a keypad.
    Grid {
        id: logo
        anchors.centerIn: parent
        columns: 3
        spacing: 2

        Repeater {
            // Row-major from the top left; true = part of the "t".
            model: [false, false, false,
                    true,  true,  true,
                    false, true,  false]

            Rectangle {
                required property var modelData
                width: 4
                height: 4
                radius: width / 2
                antialiasing: true
                color: root.labelColor
                opacity: modelData ? 1.0 : 0.4
            }
        }
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

    // The state arriving is what ends a toggle. QML rejects a second handler for
    // the same signal on the same object, so both live here.
    onConnectedChanged: {
        if (!connected) peers = [];
        toggling = false;
    }

    // `tailscale up`/`down` takes seconds and tailscale.sh --toggle sleeps 5
    // more, so the menu's button reports the wait rather than looking dead.
    // Cleared by onConnectedChanged in the normal case; this only covers a
    // toggle that never lands -- `tailscale up` waiting on a login, say --
    // which would otherwise leave the button disabled for the session.
    property bool toggling: false

    Timer {
        id: toggleGuard
        interval: 20000
        onTriggered: root.toggling = false
    }

    function toggle() {
        if (toggling) return;
        root.toggling = true;
        toggleGuard.restart();
        Quickshell.execDetached(["bash", "-lc", root.toggleCommand]);
        // Poll hard until the new state shows up, instead of waiting out
        // the 3s tick -- the same thing a double-click toggle did.
        root.pollFast();
    }

    menu: tsMenu
    onClicked: root.menuOpen ? tsMenu.requestClose() : root.openMenu()
    onRightClicked: root.toggle()

    TailscaleMenu {
        id: tsMenu
        anchorItem: root
        connected: root.connected
        exitNode: root.exitNode
        peers: root.peers
        toggling: root.toggling

        // The peer poll only ticks every 10s, so ask once on the way open
        // rather than showing a list up to that stale.
        onOpenChanged: if (open && root.connected && !peerProc.running) peerProc.running = true;

        onToggleRequested: root.toggle()

        onGetFileRequested: Quickshell.execDetached(["bash", "-lc", root.getFileCommand])
    }
}
