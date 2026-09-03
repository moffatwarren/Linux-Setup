import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

// One glyph, no text: which way the machine is on the network, and nothing
// else. The SSID, signal, IP and rates it used to spell out (waybar drew the
// essid and its strength on wifi, the address on ethernet) all live in the
// hover panel, which is where you look when you want a number -- the bar
// itself only has to answer "am I on, and over what".
//
// Quickshell's NetworkDevice.address is the MAC, not the IP, and no IP is
// exposed anywhere on the device or its network object -- so the address is
// read from `ip` instead. It re-reads when the active device changes rather
// than on a poll, with a slow backstop for lease renewals.
Pill {
    id: root

    readonly property var devices: Networking.devices.values
    readonly property var active: {
        const up = devices.filter(d => d.connected);
        if (up.length === 0) return null;
        // Prefer a wired link when both are up, matching typical desktop use.
        const wired = up.filter(d => d.type === DeviceType.Wired);
        return wired.length > 0 ? wired[0] : up[0];
    }

    // Whether this machine has wifi hardware at all, connected or not -- it is
    // what separates a disconnected laptop from a disconnected desktop, and so
    // which "nothing is up" glyph to draw. The device is listed while it is
    // down (verified: wlan0 is in Networking.devices while disconnected), so
    // there is nothing to ask NetworkManager separately.
    readonly property bool wifiCapable: devices.some(d => d.type === DeviceType.Wifi)

    // The WifiNetwork the active device is actually on. NetworkDevice exposes
    // no `network` property -- only `networks`, the list of everything in range
    // (verified against quickshell-network.qmltypes: type, name, networks,
    // address, connected, state, nmManaged, autoconnect, and nothing else) --
    // so the current one is the connected member of that list. Reading a
    // `.network` that does not exist is not an error in QML, just undefined,
    // which is why this failed silently: the panel showed the fallback "Wi-Fi"
    // instead of the SSID and dropped the Signal row entirely.
    readonly property var activeNetwork: {
        if (!active || active.type !== DeviceType.Wifi) return null;
        const on = active.networks.values.filter(n => n.connected);
        return on.length > 0 ? on[0] : null;
    }

    // 0..1, not 0-100 -- the same scale WifiMenu's signal meter reads, and -1
    // for "not on wifi". Verified against a live scan: 0.92, 0.45, not 92/45.
    // signalStrength is a WifiNetwork property, not a NetworkDevice one.
    readonly property real wifiSignal: {
        const net = activeNetwork;
        return net && net.signalStrength !== undefined ? net.signalStrength : -1;
    }

    property string ipAddress: ""

    // --- throughput ---------------------------------------------------------
    // Quickshell's Networking exposes no byte counters, so rates come from the
    // kernel's own totals in sysfs. FileView reads them without spawning a
    // process, which matters for a once-a-second sample.
    property real rxRate: 0     // bytes/sec
    property real txRate: 0
    property real lastRx: -1
    property real lastTx: -1

    readonly property string ifacePath: active ? "/sys/class/net/" + active.name + "/statistics/" : ""

    function humanRate(bytesPerSec) {
        if (bytesPerSec < 1024) return Math.round(bytesPerSec) + " B/s";
        if (bytesPerSec < 1024 * 1024) return (bytesPerSec / 1024).toFixed(1) + " KiB/s";
        return (bytesPerSec / (1024 * 1024)).toFixed(2) + " MiB/s";
    }

    FileView { id: rxFile; path: root.ifacePath.length > 0 ? root.ifacePath + "rx_bytes" : ""; blockLoading: true }
    FileView { id: txFile; path: root.ifacePath.length > 0 ? root.ifacePath + "tx_bytes" : ""; blockLoading: true }

    Timer {
        interval: 1000
        running: root.ifacePath.length > 0
        repeat: true
        onTriggered: {
            rxFile.reload();
            txFile.reload();
            const r = parseFloat(rxFile.text());
            const t = parseFloat(txFile.text());
            if (isNaN(r) || isNaN(t)) return;
            // First sample after start or an interface change has no baseline.
            if (root.lastRx >= 0 && r >= root.lastRx) root.rxRate = r - root.lastRx;
            if (root.lastTx >= 0 && t >= root.lastTx) root.txRate = t - root.lastTx;
            root.lastRx = r;
            root.lastTx = t;
        }
    }

    function refreshIp() {
        if (!active) {
            ipAddress = "";
            return;
        }
        ipProc.command = ["bash", "-lc", "ip -4 -br addr show " + active.name + " | awk '{print $3}'"];
        ipProc.running = true;
    }

    onActiveChanged: {
        refreshIp();
        // Not merely stale but unknown: the old link's address is not this
        // link's, and a wrong address is worse than a missing row.
        publicIp = "";
        publicIpStale = true;
        lastRx = -1;
        lastTx = -1;
        rxRate = 0;
        txRate = 0;
    }
    Component.onCompleted: refreshIp()

    Process {
        id: ipProc
        stdout: StdioCollector {
            onStreamFinished: root.ipAddress = text.trim()
        }
    }

    // --- public IP ----------------------------------------------------------
    // Unlike the interface address this one has to be asked of somebody else's
    // server, so it is fetched on hover rather than polled -- the panel is its
    // only consumer, and an idle bar should ask nobody anything. public-ip.sh
    // caches for ten minutes, so a run of hovers costs one `cat` apiece.
    property string publicIp: ""
    // A link change makes the cached address the one answer that is certainly
    // wrong, so the next fetch has to go past the cache. It starts set because
    // a cache surviving from a previous session is in exactly that position.
    property bool publicIpStale: true

    function refreshPublicIp() {
        if (pubIpProc.running) return;
        pubIpProc.command = ["bash", "-lc",
            "~/.config/hypr/scripts/public-ip.sh" + (publicIpStale ? " --force" : "")];
        pubIpProc.running = true;
    }

    Process {
        id: pubIpProc
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim();
                // The script prints nothing rather than guessing, so an empty
                // answer means "ask again later", not "you have no address".
                if (v.length === 0) return;
                root.publicIp = v;
                root.publicIpStale = false;
            }
        }
    }

    onHoveredChanged: if (hovered) refreshPublicIp()

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: if (!ipProc.running) root.refreshIp()
    }

    // Material Design Icons from the nerd font, as surrogate pairs (see
    // CLAUDE.md) -- the family AudioPill draws from, and the one with a
    // slashed counterpart for each of these states. The shape says which
    // medium, the slash says whether it is up, and `labelColor` still turns
    // the whole thing red when nothing is connected, as it did the old text.
    label: {
        if (active)
            return active.type === DeviceType.Wifi
                ? "\udb81\udda9"      // wifi
                : "\udb80\ude00";     // ethernet
        return wifiCapable
            ? "\udb81\uddaa"          // wifi-off
            : "\udb80\ude02";         // ethernet-cable-off
    }
    labelColor: active ? Theme.text : Theme.red

    // Left-click opens the wifi picker; nmtui is still reachable from inside it.
    // Left rather than right to match BluetoothPill and NotificationPill, which
    // both put their menu on the primary button. The right button is unbound
    // here -- the wifi radio toggle lives in the menu header, unlike the
    // bluetooth adapter, which has it on both.
    onClicked: wifiMenu.open = !wifiMenu.open

    WifiMenu {
        id: wifiMenu
        anchorItem: root
    }

    ListPopup {
        anchorItem: root
        requested: root.hovered && !wifiMenu.open
        title: root.active ? String(root.active.name) : "Network"
        emptyText: root.active ? "" : "No active connection"
        rows: {
            if (!root.active) return [];
            const out = [];
            // Wifi leads with what the bar no longer says: which network, and
            // how well. The strength takes an accent rather than a bare number
            // because the bar's idiom is that the colour is the readout.
            if (root.active.type === DeviceType.Wifi) {
                const net = root.activeNetwork;
                out.push({ text: "Network", detail: net ? String(net.name) : "Wi-Fi" });
                if (root.wifiSignal >= 0)
                    out.push({
                        text: "Signal",
                        detail: Math.round(root.wifiSignal * 100) + "%",
                        accent: root.wifiSignal >= 0.67 ? Theme.green
                              : root.wifiSignal >= 0.34 ? Theme.yellow : Theme.red
                    });
            }
            out.push({ text: "\u2193 Download", detail: root.humanRate(root.rxRate), accent: Theme.green });
            out.push({ text: "\u2191 Upload",   detail: root.humanRate(root.txRate), accent: Theme.sapphire });
            if (root.ipAddress.length > 0) out.push({ text: "IP", detail: root.ipAddress });
            if (root.publicIp.length > 0) out.push({ text: "Public IP", detail: root.publicIp });
            out.push({ text: "MAC", detail: String(root.active.address) });
            return out;
        }
    }
}
