import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

// The dropdown for a tray icon: the app's own DBus menu, drawn in the
// Catppuccin frame every other menu here uses (PowerMenu, WifiMenu,
// NotificationMenu -- base inside a surface1 border).
//
// Quickshell can hand the menu straight to Qt with `trayItem.display(...)`,
// which is one line instead of two files. It is not used because that draws a
// stock Qt platform menu: the wrong font, the wrong colours and a square
// frame, hanging off the one bar that is otherwise entirely Mocha. Same reason
// ListPopup exists instead of the QtQuick ToolTip.
//
// One instance lives in TrayPill and is re-anchored to whichever icon was
// clicked, rather than one menu per icon.
PopupWindow {
    id: root

    property Item anchorItem: null
    property var trayItem: null
    property bool open: false

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 6

    implicitWidth: 260
    implicitHeight: body.implicitHeight + 20
    color: "transparent"
    visible: open && anchorItem !== null
    // Needed for Escape; the focus grab below is what closes the menu on a
    // click anywhere outside it.
    grabFocus: open

    HyprlandFocusGrab {
        windows: [root]
        active: root.open
        onCleared: root.close()
    }

    // An app can quit with its menu open. QML nulls an Item-typed property when
    // its object is destroyed, so this is the signal that the anchor icon has
    // gone -- without it `open` stays true and the focus grab keeps swallowing
    // clicks for an invisible window.
    onAnchorItemChanged: if (!root.anchorItem) root.close()

    function show(item, anchor) {
        root.trayItem = item;
        root.anchorItem = anchor;
        root.open = true;
    }

    function close() { root.open = false; }

    Rectangle {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.close()
        radius: 12
        color: Theme.base
        border.width: 1
        border.color: Theme.surface1

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 5

            Text {
                Layout.fillWidth: true
                text: {
                    if (!root.trayItem) return "";
                    const name = String(root.trayItem.title ?? "");
                    return name.length > 0 ? name : String(root.trayItem.id ?? "");
                }
                elide: Text.ElideRight
                color: Theme.lavender
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface1 }

            TrayMenuItems {
                Layout.fillWidth: true
                // Dropped when the menu closes: DBusMenu is a pull protocol
                // and apps only keep a menu current while a host says it is
                // open, so holding the handle open would leave a stale menu
                // being polled all day.
                handle: root.open && root.trayItem ? root.trayItem.menu : null
                onActivated: root.close()
            }
        }
    }
}
