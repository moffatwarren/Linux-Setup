import Quickshell
import Quickshell.Hyprland
import QtQuick

// waybar: "hyprland/workspaces" with all-outputs:false, format "{name}".
// style.css: lavender circles, active = crust on lavender, urgent = red.
// Sized off Theme.pillHeight so the module is exactly as tall as every other
// pill in the bar; the dots are inset by 2px a side to sit inside that height.
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

    // Diameter of one workspace dot, inset inside the pill.
    readonly property int dotSize: Theme.pillHeight - 4

    visible: workspaces.length > 0
    implicitWidth: row.implicitWidth + 8
    implicitHeight: Theme.pillHeight
    radius: height / 2
    color: Theme.pill

    function scrollWorkspace(delta) {
        if (workspaces && workspaces.length > 1) {
            let activeIndex = -1;
            for (let i = 0; i < workspaces.length; i++) {
                if (workspaces[i].active) {
                    activeIndex = i;
                    break;
                }
            }
            if (activeIndex === -1) activeIndex = 0;

            let targetIndex;
            if (delta > 0) {
                targetIndex = (activeIndex - 1 + workspaces.length) % workspaces.length;
            } else if (delta < 0) {
                targetIndex = (activeIndex + 1) % workspaces.length;
            } else {
                return;
            }
            workspaces[targetIndex].activate();
        } else {
            const dir = delta > 0 ? "e-1" : "e+1";
            Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ workspace = "${dir}" })`]);
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onWheel: wheel => root.scrollWorkspace(wheel.angleDelta.y)
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            model: root.workspaces

            Item {
                required property var modelData
                width: root.dotSize + 8
                height: root.dotSize

                Rectangle {
                    anchors.centerIn: parent
                    width: root.dotSize
                    height: root.dotSize
                    radius: width / 2
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
                        onWheel: wheel => root.scrollWorkspace(wheel.angleDelta.y)
                    }
                }
            }
        }
    }
}
