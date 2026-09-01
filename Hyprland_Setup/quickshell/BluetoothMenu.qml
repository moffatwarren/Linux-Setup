import Quickshell
import Quickshell.Hyprland
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts

// Right-click dropdown on the bluetooth module: connect, disconnect, pair and
// forget devices without opening blueman. Mirrors WifiMenu.
PopupWindow {
    id: root

    property Item anchorItem: null
    property bool open: false

    readonly property var adapter: Bluetooth.defaultAdapter

    // Devices we have a relationship with, connected first.
    readonly property var pairedDevices: {
        return Bluetooth.devices.values
            .filter(d => d.paired || d.bonded)
            .sort((a, b) => {
                if (a.connected !== b.connected) return a.connected ? -1 : 1;
                return String(a.name).localeCompare(String(b.name));
            });
    }

    // Everything else that is advertising. Unnamed entries come through as a
    // bare MAC -- those are BLE beacons and are pure noise in a picker.
    readonly property var nearbyDevices: {
        const isMac = /^([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}$/;
        return Bluetooth.devices.values
            .filter(d => !d.paired && !d.bonded && !isMac.test(String(d.name)))
            .sort((a, b) => String(a.name).localeCompare(String(b.name)))
            .slice(0, 6);
    }

    function glyphFor(device) {
        const icon = String(device.icon || "");
        if (icon.indexOf("gaming") !== -1) return "\uf11b";
        if (icon.indexOf("audio") !== -1 || icon.indexOf("headset") !== -1) return "\uf025";
        if (icon.indexOf("phone") !== -1) return "\uf10b";
        if (icon.indexOf("keyboard") !== -1) return "\uf11c";
        if (icon.indexOf("mouse") !== -1) return "\uf245";
        return "\uf294";
    }

    function stateText(device) {
        switch (device.state) {
        case BluetoothDeviceState.Connected:     return "connected";
        case BluetoothDeviceState.Connecting:    return "connecting";
        case BluetoothDeviceState.Disconnecting: return "disconnecting";
        default: return device.pairing ? "pairing" : "";
        }
    }

    function stateColor(device) {
        switch (device.state) {
        case BluetoothDeviceState.Connected:  return Theme.green;
        case BluetoothDeviceState.Connecting:
        case BluetoothDeviceState.Disconnecting: return Theme.yellow;
        default: return Theme.overlay0;
        }
    }

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 6

    implicitWidth: 300
    implicitHeight: body.implicitHeight + 20
    color: "transparent"
    visible: open

    // Scan only while the menu is on screen. A Binding rather than an
    // onOpenChanged handler, which would not fire if open were already true.
    Binding {
        target: root.adapter
        property: "discovering"
        value: root.open && root.adapter !== null && root.adapter.enabled
        when: root.adapter !== null
    }

    // Dismiss when the user clicks anywhere outside the menu. A layer-shell
    // popup gets no such event on its own; Hyprland's focus grab reports it.
    HyprlandFocusGrab {
        windows: [root]
        active: root.open
        onCleared: root.close()
    }

    function close() { open = false; }

    // Paired devices toggle their connection; new ones get paired.
    function activate(device) {
        if (device.connected) device.disconnect();
        else if (device.paired || device.bonded) device.connect();
        else device.pair();
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
            spacing: 5

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Bluetooth"
                    color: Theme.lavender
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Text {
                    visible: root.adapter !== null && root.adapter.discovering
                    text: "scanning"
                    color: Theme.yellow
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                }

                Text {
                    text: root.adapter && root.adapter.enabled ? "on" : "off"
                    color: root.adapter && root.adapter.enabled ? Theme.green : Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface1 }

            Text {
                Layout.fillWidth: true
                visible: !root.adapter || !root.adapter.enabled
                text: "Adapter is off"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            // --- paired -----------------------------------------------------
            Repeater {
                model: root.pairedDevices

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 24
                    radius: 6
                    color: pairedMouse.containsMouse ? Theme.surface0 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 8

                        Text {
                            text: root.glyphFor(modelData)
                            color: modelData.connected ? Theme.green : Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                            color: modelData.connected ? Theme.green : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        Text {
                            visible: modelData.batteryAvailable
                            text: Math.round(modelData.battery * 100) + "%"
                            color: Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        Text {
                            text: root.stateText(modelData)
                            color: root.stateColor(modelData)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }

                    MouseArea {
                        id: pairedMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) modelData.forget();
                            else root.activate(modelData);
                        }
                    }
                }
            }

            // --- discovered -------------------------------------------------
            Text {
                Layout.fillWidth: true
                visible: root.nearbyDevices.length > 0
                text: "Nearby"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }

            Repeater {
                model: root.nearbyDevices

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 24
                    radius: 6
                    color: nearbyMouse.containsMouse ? Theme.surface0 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 8

                        Text {
                            text: root.glyphFor(modelData)
                            color: Theme.overlay0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        Text {
                            text: modelData.pairing ? "pairing" : "pair"
                            color: modelData.pairing ? Theme.yellow : Theme.overlay0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }

                    MouseArea {
                        id: nearbyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.activate(modelData)
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface1 }

            Text {
                text: "Open blueman\u2026"
                color: blueMouse.containsMouse ? Theme.lavender : Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2

                MouseArea {
                    id: blueMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Quickshell.execDetached(["blueman-manager"]);
                        root.close();
                    }
                }
            }
        }
    }
}
