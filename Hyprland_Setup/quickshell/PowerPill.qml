import Quickshell
import QtQuick

// Rightmost module: a power button that opens PowerMenu. Unlike the other
// modules this opens on a left-click -- opening the menu is the button's only
// purpose, so making it the primary action rather than right-click is clearer.
Pill {
    id: root

    label: "\uf011"
    labelColor: powerMenu.open ? Theme.red : Theme.maroon

    onClicked: powerMenu.open = !powerMenu.open

    PowerMenu {
        id: powerMenu
        anchorItem: root
    }
}
