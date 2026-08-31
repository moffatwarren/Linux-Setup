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

    function refreshIp() {
        if (!active) {
            ipAddress = "";
            return;
        }
        ipProc.command = ["bash", "-lc", "ip -4 -br addr show " + active.name + " | awk '{print $3}'"];
        ipProc.running = true;
    }

    onActiveChanged: refreshIp()
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

    onRightClicked: Quickshell.execDetached(["kitty", "--class", "nmtui-floating", "-e", "nmtui"])
}
