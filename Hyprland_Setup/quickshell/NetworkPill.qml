import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

// waybar: "network" -- wifi shows "{essid} ({signalStrength}%) ", ethernet
// shows "{ipaddr}/{cidr}", disconnected shows "Disconnected ⚠".
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

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: if (!ipProc.running) root.refreshIp()
    }

    label: {
        if (!active) return "Disconnected ⚠";
        if (active.type === DeviceType.Wifi) {
            const net = active.network;
            const ssid = net ? String(net.name) : "Wi-Fi";
            const sig = net && net.signalStrength !== undefined ? " (" + net.signalStrength + "%)" : "";
            return ssid + sig + " \uf1eb";
        }
        return ipAddress.length > 0 ? ipAddress : (String(active.name) + " (No IP) \uf796");
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
            const out = [
                { text: "\u2193 Download", detail: root.humanRate(root.rxRate), accent: Theme.green },
                { text: "\u2191 Upload",   detail: root.humanRate(root.txRate), accent: Theme.sapphire }
            ];
            if (root.ipAddress.length > 0) out.push({ text: "IP", detail: root.ipAddress });
            out.push({ text: "MAC", detail: String(root.active.address) });
            return out;
        }
    }
}
