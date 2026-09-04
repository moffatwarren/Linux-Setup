import Quickshell
import QtQuick

// The notification module, immediately right of the network one.
//
// Left-click opens NotificationMenu (the list plus the mute toggle),
// right-click mutes without opening anything -- the same shortcut/menu split
// the bluetooth and network modules use.
//
// Glyphs are FA private-use codepoints and must stay as \u escapes; pasting
// them literally yields an empty string and the pill disappears.
Pill {
    id: root

    // Which bar this is, so SUPER+N can open the menu on the focused monitor
    // only. Fed by Bar.qml, the way WorkspacesPill's is.
    property string monitorName: ""

    readonly property bool muted: NotificationService.dnd
    readonly property int count: NotificationService.count

    label: {
        const glyph = root.muted ? "\uf1f6"            // bell-slash
                    : root.count > 0 ? "\uf0f3"        // bell, filled
                    : "\uf0a2";                        // bell, outline
        return root.count > 0 ? glyph + " " + root.count : glyph;
    }

    // Muted reads as dimmed rather than as another colour, so "off" is obvious
    // without having to know what the colour means.
    labelColor: root.muted ? Theme.overlay0
              : NotificationService.hasCritical ? Theme.red
              : root.count > 0 ? Theme.yellow
              : Theme.teal

    onClicked: NotificationService.toggleMenu(root.monitorName)
    onRightClicked: NotificationService.toggleDnd()

    NotificationMenu {
        id: menu
        anchorItem: root
        // One menu across all bars: the service holds which monitor owns it, so
        // a second monitor's pill cannot open a duplicate.
        open: NotificationService.menuMonitor === root.monitorName
    }
}
