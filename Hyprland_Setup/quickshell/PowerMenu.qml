import Quickshell
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
MenuPopup {
    id: root

    readonly property var actions: [
        { label: "Lock",     glyph: "\uf023", accent: Theme.sapphire, command: "hyprlock" },
        { label: "Sleep",    glyph: "\uf186", accent: Theme.blue,     command: "hyprlock & sleep 0.5 && systemctl suspend" },
        { label: "Log out",  glyph: "\uf08b", accent: Theme.mauve,    command: "hyprctl dispatch 'hl.dsp.exit()'" },
        { label: "Restart",  glyph: "\uf021", accent: Theme.peach,    command: "systemctl reboot" },
        { label: "Shutdown", glyph: "\uf011", accent: Theme.red,      command: "systemctl poweroff" }
    ]

    implicitWidth: 170
    implicitHeight: body.implicitHeight + 20

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.popupPad
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
                        root.requestClose();
                        Quickshell.execDetached(["bash", "-lc", modelData.command]);
                    }
                }
            }
        }
    }
}
