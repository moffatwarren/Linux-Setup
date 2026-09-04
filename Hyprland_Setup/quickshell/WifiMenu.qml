import Quickshell
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts

// Left-click dropdown on the network module: what the link is doing, at the
// top, and then the wifi networks to pick from.
//
// The status block is what used to be the pill's hover panel. NetworkPill works
// all of it out -- the SSID and its strength, the interface address, the
// throughput, the public IP -- and this only draws it, the split PiaMenu and
// TailscaleMenu use. It sits above the network list because it answers "what am
// I on", which is the question you have when you open this without meaning to
// change anything.
//
// Signal strength is drawn as four bars rather than a nerd font glyph -- the
// private-use codepoints are easy to get wrong, and this scales cleanly -- plus
// the percentage beside the name, for picking between two networks that both
// light three bars.
MenuPopup {
    id: root

    // --- the active link, all computed by NetworkPill ----------------------
    property bool hasActive: false
    property bool activeIsWifi: false
    property string deviceName: ""
    property string ssid: ""
    // 0..1, or -1 when the active link is not wifi.
    property real signalStrength: -1
    property string ipAddress: ""
    property string publicIp: ""
    property string macAddress: ""
    property real rxRate: 0
    property real txRate: 0

    // Formatting lives here rather than in the pill, which has no label to put
    // a rate in -- the same division weather-forecast.sh and system-stats.sh
    // have with the modules that draw them.
    function humanRate(bytesPerSec) {
        if (bytesPerSec < 1024) return Math.round(bytesPerSec) + " B/s";
        if (bytesPerSec < 1024 * 1024) return (bytesPerSec / 1024).toFixed(1) + " KiB/s";
        return (bytesPerSec / (1024 * 1024)).toFixed(2) + " MiB/s";
    }

    readonly property var statusRows: {
        if (!hasActive) return [];
        const out = [];
        if (activeIsWifi) {
            out.push({ text: "Network", detail: ssid.length > 0 ? ssid : "Wi-Fi",
                       accent: Theme.text });
            if (signalStrength >= 0)
                out.push({ text: "Signal",
                           detail: Math.round(signalStrength * 100) + "%",
                           accent: signalStrength >= 0.67 ? Theme.green
                                 : signalStrength >= 0.34 ? Theme.yellow : Theme.red });
        }
        out.push({ text: "\u2193 Download", detail: humanRate(rxRate), accent: Theme.green });
        out.push({ text: "\u2191 Upload",   detail: humanRate(txRate), accent: Theme.sapphire });
        if (ipAddress.length > 0)
            out.push({ text: "IP", detail: ipAddress, accent: Theme.subtext0 });
        if (publicIp.length > 0)
            out.push({ text: "Public IP", detail: publicIp, accent: Theme.subtext0 });
        if (macAddress.length > 0)
            out.push({ text: "MAC", detail: macAddress, accent: Theme.subtext0 });
        return out;
    }

    readonly property var wifiDevice: {
        const l = Networking.devices.values.filter(d => d.type === DeviceType.Wifi);
        return l.length > 0 ? l[0] : null;
    }

    // One entry per SSID, strongest first. Quickshell lists each access point
    // separately, so a network visible on two APs would otherwise appear twice.
    readonly property var networks: {
        if (!wifiDevice) return [];
        const best = ({});
        for (const n of wifiDevice.networks.values) {
            const name = String(n.name || "");
            if (name.length === 0) continue;
            if (!best[name] || n.signalStrength > best[name].signalStrength) best[name] = n;
        }
        return Object.keys(best)
            .map(k => best[k])
            .sort((a, b) => {
                if (a.connected !== b.connected) return a.connected ? -1 : 1;
                return b.signalStrength - a.signalStrength;
            })
            // Keep the menu a sane height in a crowded area.
            .slice(0, 8);
    }

    // The network awaiting a password, if any.
    property var pendingNetwork: null

    // 300 before the per-row percentage column; widened so an SSID still has
    // room beside it rather than eliding a character earlier on every row.
    implicitWidth: 340
    implicitHeight: body.implicitHeight + 20
    // Held whenever the menu is open, so Escape closes it and the password
    // field can receive key events.

    // Scanning is opt-in, behind the Scan button, exactly as BluetoothMenu's
    // discovery is. It used to start the instant the menu opened, so every
    // glance at "what am I connected to" powered up a scan -- and the list
    // re-sorted itself by signal under the pointer while you were aiming at a
    // row.
    //
    // **The list is empty until the button is pressed, and that is not a bug to
    // fix by scanning a little bit anyway.** `NetworkDevice.networks` is
    // populated only while `scannerEnabled` is true -- verified: 0 with the
    // scanner off while NetworkManager itself held 41 access points, 10 within
    // 1.5 s of enabling it, 0 again on disabling. So there is no cached list to
    // fall back on here. NetworkPill reads the *connected* network's name and
    // strength out of NM's own cache with `nmcli --rescan no`, which is why the
    // status block above still has them with the radio idle; that trick does
    // not extend to the list, because a row has to be a WifiNetwork object to
    // be connected to or forgotten.
    //
    // A Binding rather than an onOpenChanged handler, which would never fire if
    // `open` were already true at construction.
    property bool scanRequested: false
    readonly property bool scanning: wifiDevice !== null && wifiDevice.scannerEnabled

    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: root.open && root.scanRequested && Networking.wifiEnabled
        when: root.wifiDevice !== null
    }

    // Every opening starts quiet. Leaving the request set would silently resume
    // the scan next time, which is the behaviour this replaced.
    onOpenChanged: if (!open) { pendingNetwork = null; scanRequested = false; }

    // Take the keyboard back from the password field when it goes away, so
    // the next Escape closes the menu.
    onPendingNetworkChanged: if (pendingNetwork === null) root.panel.forceActiveFocus()

    function requestClose() {
        pendingNetwork = null;
        open = false;
    }

    function activate(net) {
        if (net.connected) {
            net.disconnect();
            requestClose();
        } else if (net.known || net.security === WifiSecurityType.Open) {
            net.connect();
            requestClose();
        } else {
            // Secured and never joined before -- ask for the passphrase.
            pendingNetwork = net;
        }
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.popupPad
        spacing: 6

        // The title names the interface that is actually carrying traffic,
        // which on a machine with both is the first thing worth knowing --
        // the pill is one glyph and cannot say `eth0` or `wlan0`.
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: root.hasActive && root.deviceName.length > 0
                      ? root.deviceName : "Network"
                color: Theme.lavender
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            // The wifi radio, which is a property of the machine rather
            // than of the active link -- so it stays here on a wired box
            // whose title says `eth0`.
            Text {
                text: "Wi-Fi " + (Networking.wifiEnabled ? "on" : "off")
                color: Networking.wifiEnabled ? Theme.green : Theme.overlay0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.surface1
        }

        // --- the status block, ex-hover-panel ---------------------------
        Text {
            Layout.fillWidth: true
            visible: !root.hasActive
            text: "No active connection"
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Repeater {
            model: root.statusRows

            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 16

                Text {
                    text: modelData.text
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Item { Layout.fillWidth: true }

                Text {
                    // Capped so a long SSID elides instead of stretching
                    // the menu, the job ListPopup's maxDetailWidth did.
                    Layout.maximumWidth: 190
                    text: modelData.detail
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    color: modelData.accent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
        }

        // --- the networks -----------------------------------------------
        // This row is visible whenever the radio is on rather than only
        // when networks have been found: it carries the Scan button, and
        // gating it on the list would hide the only control that refreshes
        // it -- the same trap BluetoothMenu's "Nearby" header had.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: Networking.wifiEnabled

            Text {
                text: "Networks"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitWidth: scanLabel.implicitWidth + 16
                implicitHeight: 20
                radius: 6
                color: scanMouse.containsMouse ? Theme.surface1 : Theme.surface0
                border.width: 1
                border.color: Theme.surface2

                Text {
                    id: scanLabel
                    // Reads the device's own scannerEnabled, not the
                    // request, so a scan NetworkManager refused cannot
                    // leave the button claiming to be running.
                    text: root.scanning ? "Scanning\u2026" : "Scan"
                    color: root.scanning ? Theme.yellow : Theme.text
                    anchors.centerIn: parent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                MouseArea {
                    id: scanMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.scanRequested = !root.scanRequested
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.networks.length === 0
            text: !Networking.wifiEnabled ? "Wi-Fi is off"
                : root.scanning ? "Searching\u2026"
                : "No networks yet \u2014 press Scan"
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        Repeater {
            model: root.networks

            Rectangle {
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: 24
                radius: 6
                color: rowMouse.containsMouse ? Theme.surface0 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 8

                    // Four-bar signal meter
                    Row {
                        spacing: 2
                        Repeater {
                            model: 4
                            Rectangle {
                                required property int index
                                width: 3
                                height: 4 + index * 3
                                y: 13 - height
                                radius: 1
                                color: (modelData.signalStrength * 4) > index
                                    ? (modelData.connected ? Theme.green : Theme.text)
                                    : Theme.surface2
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        elide: Text.ElideRight
                        color: modelData.connected ? Theme.green : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    // The same number NetworkPill's hover panel shows, on
                    // the same thresholds, so the two cannot disagree.
                    // signalStrength is 0..1, not 0-100. Right-aligned in a
                    // fixed column so the lock and "saved" markers sit at
                    // the same x on every row.
                    Text {
                        Layout.preferredWidth: 30
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(modelData.signalStrength * 100) + "%"
                        color: modelData.signalStrength >= 0.67 ? Theme.green
                             : modelData.signalStrength >= 0.34 ? Theme.yellow
                             : Theme.red
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }

                    // Lock for anything that is not an open network
                    Text {
                        visible: modelData.security !== WifiSecurityType.Open
                        text: "\uf023"
                        color: Theme.overlay0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }

                    Text {
                        visible: modelData.known && !modelData.connected
                        text: "saved"
                        color: Theme.overlay0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            if (modelData.known) modelData.forget();
                        } else {
                            root.activate(modelData);
                        }
                    }
                }
            }
        }

        // Passphrase entry, shown only for a secured network we have not joined
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.pendingNetwork !== null
            spacing: 4

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Theme.surface1
            }

            Text {
                text: root.pendingNetwork ? "Password for " + root.pendingNetwork.name : ""
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 24
                radius: 6
                color: Theme.surface0
                border.width: 1
                border.color: Theme.surface2

                TextInput {
                    id: pskField
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    selectByMouse: true
                    focus: root.pendingNetwork !== null

                    onAccepted: {
                        if (text.length > 0 && root.pendingNetwork) {
                            root.pendingNetwork.connectWithPsk(text);
                            text = "";
                            root.requestClose();
                        }
                    }
                    Keys.onEscapePressed: {
                        text = "";
                        root.pendingNetwork = null;
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Theme.surface1
        }

        // Escape hatch for anything this menu does not cover
        Text {
            text: "Open nmtui…"
            color: nmtuiMouse.containsMouse ? Theme.lavender : Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2

            MouseArea {
                id: nmtuiMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Quickshell.execDetached(["kitty", "--class", "nmtui-floating", "-e", "nmtui"]);
                    root.requestClose();
                }
            }
        }
    }
}
