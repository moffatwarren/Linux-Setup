import Quickshell
import Quickshell.Hyprland
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts

// Right-click dropdown on the network module: pick and connect to a wifi
// network without leaving the bar.
//
// Signal strength is drawn as four bars rather than a nerd font glyph -- the
// private-use codepoints are easy to get wrong, and this scales cleanly.
PopupWindow {
    id: root

    property Item anchorItem: null
    property bool open: false

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

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 6

    implicitWidth: 300
    implicitHeight: body.implicitHeight + 20
    color: "transparent"
    visible: open
    // Needed for the password field to receive key events.
    grabFocus: open && pendingNetwork !== null

    // Only scan while the menu is on screen. Declared as a Binding rather than
    // an onOpenChanged handler, which would never fire if `open` were already
    // true at construction.
    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: root.open
        when: root.wifiDevice !== null
    }

    onOpenChanged: if (!open) pendingNetwork = null

    // Dismiss when the user clicks anywhere outside the menu. A layer-shell
    // popup gets no such event on its own; Hyprland's focus grab reports it.
    HyprlandFocusGrab {
        windows: [root]
        active: root.open
        onCleared: root.close()
    }

    function close() {
        pendingNetwork = null;
        open = false;
    }

    function activate(net) {
        if (net.connected) {
            net.disconnect();
            close();
        } else if (net.known || net.security === WifiSecurityType.Open) {
            net.connect();
            close();
        } else {
            // Secured and never joined before -- ask for the passphrase.
            pendingNetwork = net;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.base
        border.width: 1
        border.color: Theme.surface1

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 6

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Wi-Fi"
                    color: Theme.lavender
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                // Radio toggle
                Text {
                    text: Networking.wifiEnabled ? "on" : "off"
                    color: Networking.wifiEnabled ? Theme.green : Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize

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

            Text {
                Layout.fillWidth: true
                visible: root.networks.length === 0
                text: Networking.wifiEnabled ? "Scanning…" : "Wi-Fi is off"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
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
                                root.close();
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
                        root.close();
                    }
                }
            }
        }
    }
}
