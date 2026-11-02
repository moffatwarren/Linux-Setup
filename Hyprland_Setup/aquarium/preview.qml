// A windowed preview, with no lock involved:  qs -p Hyprland_Setup/aquarium/preview.qml
// It runs as its own instance beside the bar. Space pauses, Escape quits.
//
// 1440x810 scales the tank by 3, which makes it 480x270: exactly the layout a 1080p
// screen gets at scale 4, just smaller. A fixed size is also what makes Hyprland
// float the window, rather than tiling it into some other shape of tank.
import QtQuick
import Quickshell

FloatingWindow {
    id: win

    title: "Aquarium preview"
    implicitWidth: 1440
    implicitHeight: 810
    minimumSize: Qt.size(1440, 810)
    maximumSize: Qt.size(1440, 810)
    color: "black"

    Aquarium {
        id: aquarium
        anchors.fill: parent
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                Qt.quit();
            else if (event.key === Qt.Key_Space)
                aquarium.running = !aquarium.running;
        }
    }
}
