import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick

// The StatusNotifierItem tray -- the one waybar module that never got carried
// over. localsend, rustdesk, teams-for-linux and spotify all minimise into it,
// and with no host on the bus they either sit in the background with no way
// back or refuse to close to tray at all.
//
// NOT a `Pill`: that draws a single Text and hides itself on an empty label,
// and this is a row of icons. It borrows Pill's geometry (height, radius,
// padding, colour) and paints its own body, the way MediaGroup does for album
// art.
Rectangle {
    id: root

    // SystemTray, like every other Quickshell service, stays empty until
    // something binds to it -- this property is what starts the host.
    readonly property var items: SystemTray.items.values

    // Which icon the pointer is on, for the shared hover panel. One panel and
    // one menu for the whole row rather than a pair per icon: they are
    // re-anchored to the delegate that asked for them.
    property var hoveredItem: null

    readonly property int iconSize: 16

    visible: items.length > 0
    implicitWidth: row.implicitWidth + Theme.pillPad * 2
    implicitHeight: Theme.pillHeight
    radius: height / 2
    color: Theme.pill

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Repeater {
            model: root.items

            Item {
                id: entry

                required property var modelData

                width: root.iconSize
                height: root.iconSize
                anchors.verticalCenter: parent.verticalCenter

                // `icon` is already a resolved source URL (image://, or a path)
                // -- IconImage takes it as-is.
                IconImage {
                    id: image
                    anchors.fill: parent
                    source: String(entry.modelData.icon ?? "")
                    asynchronous: true
                    visible: source != "" && status !== Image.Error
                }

                // An app that published no usable icon still gets a slot, so
                // its menu stays reachable rather than the icon just missing.
                Text {
                    anchors.centerIn: parent
                    visible: !image.visible
                    // Escaped, not pasted: a private-use codepoint typed literally
                    // comes through as an empty string (see CLAUDE.md).
                    text: "\uf2d0"      // window-maximize
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                // NeedsAttention is the tray's only "look at me" channel, and
                // an app that sets it (a finished transfer, an incoming call)
                // is otherwise indistinguishable from one that did not.
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -1
                    anchors.topMargin: -1
                    width: 5
                    height: 5
                    radius: 2.5
                    color: Theme.yellow
                    visible: entry.modelData.status === Status.NeedsAttention
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    onEntered: root.hoveredItem = entry.modelData
                    onExited: if (root.hoveredItem === entry.modelData) root.hoveredItem = null

                    onClicked: mouse => {
                        const item = entry.modelData;
                        if (mouse.button === Qt.MiddleButton) {
                            item.secondaryActivate();
                            return;
                        }
                        // `onlyMenu` means the app published no activate
                        // handler at all -- calling it does nothing, so a
                        // left-click has to fall through to the menu or the
                        // icon looks dead.
                        const wantMenu = mouse.button === Qt.RightButton || item.onlyMenu;
                        if (wantMenu && item.hasMenu) trayMenu.show(item, entry);
                        else if (wantMenu) item.secondaryActivate();
                        else item.activate();
                    }

                    onWheel: wheel => {
                        if (wheel.angleDelta.y !== 0)
                            entry.modelData.scroll(wheel.angleDelta.y, false);
                        if (wheel.angleDelta.x !== 0)
                            entry.modelData.scroll(wheel.angleDelta.x, true);
                    }
                }
            }
        }
    }

    ListPopup {
        anchorItem: root
        requested: root.hoveredItem !== null && !trayMenu.open
        title: {
            const item = root.hoveredItem;
            if (!item) return "";
            const tip = String(item.tooltipTitle ?? "");
            if (tip.length > 0) return tip;
            const name = String(item.title ?? "");
            return name.length > 0 ? name : String(item.id ?? "");
        }
        // The description when the app sent one, otherwise the service id --
        // which is the only thing that tells two identical grey icons apart.
        emptyText: {
            const item = root.hoveredItem;
            if (!item) return "";
            const desc = String(item.tooltipDescription ?? "");
            return desc.length > 0 ? desc : String(item.id ?? "");
        }
    }

    TrayMenu {
        id: trayMenu
    }
}
