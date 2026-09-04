import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

// Left-click dropdown on the tailscale module: the state, the exit node and
// the peer list, plus the Connect/Disconnect button that used to be the pill's
// double-click and the `tailscale file get` that used to be its right-click.
// The pill binds no other button.
//
// This was a ListPopup hover panel, and it had to stop being one the moment it
// grew a button: a hover panel is driven by `requested: root.hovered`, so it
// closes as the pointer leaves the pill -- i.e. on the way to anything inside
// it. Something you click is a dropdown, which also means it dismisses the way
// every other dropdown on this bar does: Escape, or a click anywhere outside
// via HyprlandFocusGrab.
//
// It owns no state and runs no commands. TailscalePill polls tailscale and
// knows how to make the state settle quickly after a toggle, so the button
// only reports what it is told and signals back.
PopupWindow {
    id: root

    property Item anchorItem: null
    property bool open: false

    property bool connected: false
    // Set by the pill while a toggle is in flight: `tailscale up`/`down` takes
    // seconds, and a button that keeps saying "Connect" through all of it
    // reads as a click that did nothing.
    property bool toggling: false
    property string exitNode: ""
    property var peers: []

    signal toggleRequested()
    signal getFileRequested()

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 6

    implicitWidth: 260
    implicitHeight: body.implicitHeight + 20
    color: "transparent"
    visible: open
    // Take the keyboard while open so Escape can close the menu.
    grabFocus: open

    // Dismiss on a click anywhere outside, as PowerMenu and the network,
    // bluetooth and audio menus do.
    HyprlandFocusGrab {
        windows: [root]
        active: root.open
        onCleared: root.close()
    }

    function close() { open = false; }

    Rectangle {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.close()
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

            // Title plus the primary action, in the row BluetoothMenu puts its
            // adapter toggle and its Scan button in.
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Tailscale"
                    color: Theme.lavender
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: toggleLabel.implicitWidth + 16
                    implicitHeight: 20
                    radius: 6
                    color: toggleMouse.containsMouse ? Theme.surface1 : Theme.surface0
                    border.width: 1
                    border.color: Theme.surface2

                    Text {
                        id: toggleLabel
                        anchors.centerIn: parent
                        text: root.toggling
                              ? (root.connected ? "Disconnecting\u2026" : "Connecting\u2026")
                              : (root.connected ? "Disconnect" : "Connect")
                        color: root.toggling ? Theme.yellow
                             : root.connected ? Theme.red : Theme.green
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }

                    MouseArea {
                        id: toggleMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // A second click mid-toggle would queue an `up` behind
                        // a `down`; the label already says to wait.
                        enabled: !root.toggling
                        onClicked: root.toggleRequested()
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface1 }

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Text {
                    text: "Status"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.connected ? "Connected" : "Disconnected"
                    color: root.connected ? Theme.green : Theme.red
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.connected && root.exitNode.length > 0
                spacing: 16

                Text {
                    text: "Exit node"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Item { Layout.fillWidth: true }

                Text {
                    Layout.maximumWidth: 150
                    text: root.exitNode
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    color: Theme.sapphire
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }

            // --- peers ------------------------------------------------------
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: root.connected
                text: "Peers"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }

            Text {
                Layout.fillWidth: true
                visible: root.connected && root.peers.length === 0
                text: "No peers"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }

            // Capped and clipped, the way NotificationMenu's list is: a tailnet
            // of any size must not produce a menu taller than the screen.
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 260)
                visible: root.connected && root.peers.length > 0
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.peers

                delegate: RowLayout {
                    required property var modelData
                    width: ListView.view.width
                    height: 20
                    spacing: 12

                    Text {
                        Layout.fillWidth: true
                        text: modelData.name + (modelData.exitNode ? "  (exit node)" : "")
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    Text {
                        text: modelData.online ? "online" : "offline"
                        color: modelData.online ? Theme.green : Theme.overlay0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }
            }

            // --- footer -----------------------------------------------------
            // `tailscale file get`, which was the pill's right-click before
            // that button became the way this menu opens. It sits here for the
            // same reason pavucontrol and blueman sit at the foot of theirs.
            Rectangle {
                Layout.fillWidth: true
                visible: root.connected
                implicitHeight: 1
                color: Theme.surface1
            }

            Text {
                visible: root.connected
                text: "Receive files to ~/Downloads\u2026"
                color: fileMouse.containsMouse ? Theme.lavender : Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2

                MouseArea {
                    id: fileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.getFileRequested();
                        root.close();
                    }
                }
            }
        }
    }
}
