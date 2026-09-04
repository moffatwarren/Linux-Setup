import QtQuick

// Pending package updates: a box glyph and a count, opening UpdateMenu.
//
// Nothing anywhere in the module runs the upgrade, deliberately -- that is done
// by hand in a terminal, and the menu is a readout with a Check button, not a
// control panel.
//
// That is not just a scoping decision. An upgrade needs a password and this
// session runs no polkit agent (the wall PiaMenu's Start-service button already
// hit), and pacman asks real questions mid-transaction -- replaces, conflicts,
// [Y/n] -- which a Process in the bar has no way to answer and would simply
// hang on. If a click is ever wanted here it has to open a kitty, the way
// pia.sh --start-service does, never run the transaction in-process.
//
// Left-click opens UpdateMenu, the way every pill that owns a menu does.
// Right-click re-checks without opening anything -- the menu/shortcut split
// BluetoothPill and NotificationPill use, and exactly what WeatherPill's right
// button already means (force a re-fetch). The re-check was the left button
// before there was a menu; it is also a button inside the menu, so the
// shortcut is for when you already know.
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

    onClicked: menu.open = !menu.open
    onRightClicked: UpdateService.check(true)

    UpdateMenu {
        id: menu
        anchorItem: root
    }
}
