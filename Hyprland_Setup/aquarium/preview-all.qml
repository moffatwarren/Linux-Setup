// The tank across every monitor at once, with no lock involved:
//     qs -p Hyprland_Setup/aquarium/preview-all.qml
//
// One full-screen layer per screen, all drawing the one Ocean, which is the same shape a
// session lock gives it. A visitor comes in after a few seconds instead of after a minute
// or two, since that is usually what this is run to see: the shark, or the great white or
// the diver with
//     AQUARIUM_VISITOR=bigshark qs -p Hyprland_Setup/aquarium/preview-all.qml
//     AQUARIUM_VISITOR=diver qs -p Hyprland_Setup/aquarium/preview-all.qml
// It takes no keyboard and lets clicks through, so it cannot trap anything, and it quits
// by itself once the visitor has had time to leave: a minute for the shark to cross two
// screens, a minute and a half for the slower great white, and a little longer for the
// diver's visit.
import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
    id: root

    readonly property bool diver: Quickshell.env("AQUARIUM_VISITOR") === "diver"
    readonly property bool bigShark: Quickshell.env("AQUARIUM_VISITOR") === "bigshark"

    Ocean {
        id: water
        sharkFirst: root.diver ? [9999, 9999] : [3, 5]
        diverFirst: root.diver ? [3, 5] : [9999, 9999]
        bigSharkChance: root.bigShark ? 1 : 0
    }

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
                ocean: water
                screen: modelData
            }
        }
    }

    Timer {
        interval: root.diver ? 100000 : root.bigShark ? 90000 : 60000
        running: true
        onTriggered: Qt.quit()
    }
}
