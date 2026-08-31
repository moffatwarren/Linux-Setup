import Quickshell
import Quickshell.Hyprland
import QtQuick

// waybar: "hyprland/workspaces" with all-outputs:false, format "{name}".
// style.css: 22px lavender circles, active = crust on lavender, urgent = red.
Rectangle {
    id: root

    property string monitorName: ""

    // Only this monitor's workspaces (all-outputs: false), numerically ordered.
    readonly property var workspaces: {
        const all = Hyprland.workspaces.values.filter(w => w.name !== undefined);
        const mine = all.filter(w => w.monitor && w.monitor.name === root.monitorName);
        const use = mine.length > 0 ? mine : all;
        return use.slice().sort((a, b) => {
            const na = parseInt(a.name), nb = parseInt(b.name);
            if (!isNaN(na) && !isNaN(nb)) return na - nb;
            return String(a.name).localeCompare(String(b.name));
        });
    }

    visible: workspaces.length > 0
    implicitWidth: row.implicitWidth + 8
    implicitHeight: Theme.pillHeight + 8
    radius: 25
    color: Theme.pill

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: root.workspaces

            Item {
                required property var modelData
                width: 22 + 8
                height: 22

                Rectangle {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    radius: 11
                    color: modelData.active ? Theme.lavender : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: modelData.name
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        color: modelData.active ? Theme.crust
                             : modelData.urgent ? Theme.red
                             : mouse.containsMouse ? Theme.sapphire
                             : Theme.lavender
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: modelData.activate()
                    }
                }
            }
        }
    }
}
