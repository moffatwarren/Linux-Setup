import QtQuick

// Pending package updates: a box glyph and a count, opening UpdateMenu.
//
// Left-click opens UpdateMenu, the way every pill that owns a menu does: the
// pending packages, a Check button to re-scan, and an Update button that runs
// paru -Syu in a floating terminal and has the bar re-check when it finishes.
// Right-click re-checks without opening anything -- the menu/shortcut split
// BluetoothPill and NotificationPill use, and what the weather pill's right
// button meant while there was one (force a re-fetch). The re-check was the
// left button before there was a menu; it is also a button inside the menu,
// so the shortcut is for when you already know.
Pill {
    id: root

    readonly property int count: UpdateService.count
    readonly property bool pending: count > 0

    // Material Design Icons from the nerd font, which live above U+F0000 and so
    // must be written as surrogate pairs -- pasting the glyph itself yields an
    // empty string and Pill then hides the module, which reads as a broken
    // module rather than a missing one.
    // An open box when something is waiting, the same box closed when nothing
    // is: one shape, so the module keeps its identity, with the state carried
    // by the difference -- the pairing PiaPill's open/closed shackle already
    // uses. The obvious md-package_up was tried first and rejected: it is a
    // SOLID square at this size and its arrow collapses into an illegible
    // blob, where the variant pair stays a clean outline. Rendered at
    // Theme.fontSize before choosing, which is the only way to tell.
    readonly property string icon: {
        if (UpdateService.refreshing) return "\udb81\udce6";   // md-sync
        if (pending) return "\udb80\udfd6";                    // md-package_variant
        return "\udb80\udfd7";                                 // md-package_variant_closed
    }

    // Hidden until the first answer parses: "nothing pending" and "the check
    // has never worked" are different states and neither may be drawn as the
    // other. Not hidden at zero, though -- a module that disappears when it is
    // happy cannot be told from one that has quietly died, and this is the one
    // place that distinction is the entire point.
    label: UpdateService.known ? (pending ? icon + " " + count : icon) : ""
    labelColor: pending ? Theme.yellow : Theme.overlay0

    menu: updateMenu
    onClicked: root.menuOpen ? updateMenu.requestClose() : root.openMenu()
    onRightClicked: UpdateService.check(true)

    UpdateMenu {
        id: updateMenu
        anchorItem: root
    }
}
