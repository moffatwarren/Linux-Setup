import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

// Drop-down for the power button. Commands match the equivalent keybinds in
// hypr/modules/binds.lua -- notably Sleep locks before suspending, the way
// SUPER+SHIFT+L already does, rather than suspending an unlocked session.
//
// Log out goes through the Lua dispatcher. This Hyprland uses the Lua config
// plugin, so `hyprctl dispatch` takes a Lua expression, not a bare dispatcher
// name -- `hyprctl dispatch exit` parses as an undefined identifier, errors,
// and silently does nothing. Hence the `hl.dsp.exit()` below. It is also the
// only way out of the session now: SUPER+M used to do this and has been
// removed, so nothing else calls exit.
PopupWindow {
    id: root

    property Item anchorItem: null
    property bool open: false

    readonly property var actions: [
        { label: "Lock",     glyph: "\uf023", accent: Theme.sapphire, command: "hyprlock" },
        { label: "Sleep",    glyph: "\uf186", accent: Theme.blue,     command: "hyprlock & sleep 0.5 && systemctl suspend" },
        { label: "Log out",  glyph: "\uf08b", accent: Theme.mauve,    command: "hyprctl dispatch 'hl.dsp.exit()'" },
        { label: "Restart",  glyph: "\uf021", accent: Theme.peach,    command: "systemctl reboot" },
        { label: "Shutdown", glyph: "\uf011", accent: Theme.red,      command: "systemctl poweroff" }
    ]

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 6

    implicitWidth: 170
    implicitHeight: body.implicitHeight + 20
    color: "transparent"
    visible: open
    // Take the keyboard while open so Escape can close the menu.
    grabFocus: open

    // Dismiss on a click anywhere outside, as the network and bluetooth menus do.
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
            spacing: 2

            Repeater {
                model: root.actions

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 26
                    radius: 6
                    color: itemMouse.containsMouse ? Theme.surface0 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 10

                        Text {
                            text: modelData.glyph
                            color: modelData.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.label
                            color: itemMouse.containsMouse ? modelData.accent : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                    }

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.close();
                            Quickshell.execDetached(["bash", "-lc", modelData.command]);
                        }
                    }
                }
            }
        }
    }
}
