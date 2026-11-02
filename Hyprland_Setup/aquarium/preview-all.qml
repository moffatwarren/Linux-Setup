// The tank on every monitor at once, with no lock involved:
//     qs -p Hyprland_Setup/aquarium/preview-all.qml
//
// One full-screen layer per screen, each with its own tank, which is the same shape a
// session lock gives it. It takes no keyboard and lets clicks through, so it cannot
// trap anything, and it quits by itself after 30 seconds.
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "aquarium-preview"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "black"
            mask: Region {}

            Aquarium {
                anchors.fill: parent
            }
        }
    }

    Timer {
        interval: 30000
        running: true
        onTriggered: Qt.quit()
    }
}
