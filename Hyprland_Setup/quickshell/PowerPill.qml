import Quickshell
import QtQuick

// Rightmost module: a power button that opens PowerMenu. Either mouse button
// opens it -- the menu is the button's only purpose, so there is no second
// action for right-click to do.
Pill {
    id: root

    label: "\uf011"
    labelColor: powerMenu.open ? Theme.red : Theme.maroon

    menu: powerMenu
    function toggleMenu() {
        if (root.menuOpen) powerMenu.requestClose();
        else root.openMenu();
    }

    onClicked: toggleMenu()
    onRightClicked: toggleMenu()

    PowerMenu {
        id: powerMenu
        anchorItem: root
    }
}
