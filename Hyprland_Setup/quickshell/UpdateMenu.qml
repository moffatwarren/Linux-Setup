pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

// Drop-down for the update module: what is pending, split into repo and AUR,
// with a Check button and the age of the reading.
//
// Frame, anchoring and dismissal match PowerMenu and NotificationMenu --
// Theme.base inside a surface1 border, Escape or a click outside to close.
//
// It replaced a ListPopup hover panel, which is the move CalendarPopup and
// ForecastPopup already made and for the same reason: a hover panel is
// dismissed only by moving the pointer, so it could not be read at leisure and
// had to truncate the list to a dozen rows because a panel that follows the
// cursor cannot be scrolled. A menu can, so this shows everything.
//
// It reads UpdateService directly rather than being fed by the pill, the way
// NotificationMenu reads NotificationService: the state is already in a
// singleton, so passing it through the pill would just be a second copy.
PopupWindow {
    id: root

    property Item anchorItem: null
    property bool open: false

    readonly property var repo: UpdateService.repo
    readonly property var aur: UpdateService.aur
    readonly property int count: UpdateService.count

    // Re-rendered on a timer so "12 min ago" does not sit there lying, and only
    // while the menu is actually on screen -- NotificationMenu's `now`.
    property double now: Date.now()

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 6

    implicitWidth: 380
    implicitHeight: body.implicitHeight + 20
    color: "transparent"
    visible: open
    // Take the keyboard while open so Escape can close the menu.
    grabFocus: open

    // Dismiss on a click anywhere outside, as the other module menus do -- a
    // layer-shell popup gets no such event on its own.
    HyprlandFocusGrab {
        windows: [root]
        active: root.open
        onCleared: root.close()
    }

    function close() { open = false; }

    onOpenChanged: if (open) root.now = Date.now()

    Timer {
        running: root.open
        interval: 30000
        repeat: true
        onTriggered: root.now = Date.now()
    }

    function age(stamp) {
        if (!stamp) return "never";
        const mins = Math.floor((root.now / 1000 - stamp) / 60);
        if (mins < 1) return "just now";
        if (mins < 60) return mins + " min ago";
        const hours = Math.floor(mins / 60);
        if (hours < 24) return hours + "h ago";
        return Math.floor(hours / 24) + "d ago";
    }

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
            spacing: 6

            // --- header -----------------------------------------------------
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Updates"
                    color: Theme.lavender
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Text {
                    visible: root.count > 0
                    text: root.count
                    color: Theme.yellow
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Item { Layout.fillWidth: true }

                // The re-check, which was the pill's left button before the
                // menu took it. Its label reads UpdateService.refreshing --
                // the state, not the request -- so a check that is already
                // running cannot leave the button claiming to be idle. Same
                // rule as WifiMenu's Scan button.
                Rectangle {
                    implicitWidth: checkLabel.implicitWidth + 16
                    implicitHeight: 20
                    radius: 6
                    color: checkMouse.containsMouse ? Theme.surface1 : Theme.surface0
                    border.width: 1
                    border.color: Theme.surface2

                    Text {
                        id: checkLabel
                        anchors.centerIn: parent
                        text: UpdateService.refreshing ? "Checking…" : "Check"
                        color: UpdateService.refreshing ? Theme.subtext0 : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }

                    MouseArea {
                        id: checkMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // The menu stays open: the point of pressing this is to
                        // watch the list change.
                        onClicked: UpdateService.check(true)
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface1 }

            // --- empty state ------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                visible: root.count === 0
                spacing: 6

                // Centred by filling the width and aligning the text inside
                // it, NOT by Layout.alignment: the enclosing ColumnLayout ends
                // up only as wide as its widest child, so AlignHCenter centres
                // within that narrow box and leaves the whole block sitting at
                // the left margin. Verified on screen before and after.
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "\udb80\udfd7"   // md-package_variant_closed
                    color: Theme.surface2
                    font.family: Theme.fontFamily
                    font.pixelSize: 30
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "Up to date"
                    color: Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }

            // --- the list ---------------------------------------------------
            // Capped and clipped rather than allowed to grow: a full upgrade is
            // routinely a hundred packages and the menu must not outgrow the
            // screen. Scrolls on the wheel; no scrollbar, matching the rest of
            // the bar's popups.
            //
            // A Flickable over a Column rather than a ListView, because the two
            // sections need headings between the rows and a ListView delegate
            // is one shape per row.
            Flickable {
                id: flick

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(listBody.implicitHeight, 400)
                visible: root.count > 0
                clip: true
                contentHeight: listBody.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: listBody
                    width: flick.width
                    spacing: 2

                    Repeater {
                        model: [
                            { title: "Repositories", items: root.repo, accent: Theme.subtext0 },
                            { title: "AUR",          items: root.aur,  accent: Theme.mauve }
                        ]

                        Column {
                            id: section

                            required property var modelData

                            width: listBody.width
                            spacing: 2
                            visible: section.modelData.items.length > 0

                            Item { width: 1; height: 4 }

                            Text {
                                text: section.modelData.title
                                color: Theme.subtext0
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                            }

                            Repeater {
                                model: section.modelData.items

                                Rectangle {
                                    id: row

                                    required property var modelData

                                    width: section.width
                                    implicitHeight: 24
                                    radius: 6
                                    color: rowMouse.containsMouse ? Theme.surface0 : "transparent"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 10

                                        Text {
                                            Layout.fillWidth: true
                                            text: row.modelData.name
                                            color: Theme.text
                                            elide: Text.ElideRight
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize
                                        }

                                        Text {
                                            text: row.modelData.old + " → " + row.modelData.new
                                            color: section.modelData.accent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                        }
                                    }

                                    // Hover only -- there is deliberately
                                    // nothing to click. Upgrading needs a
                                    // password and an answerable prompt, which
                                    // is a terminal's job, not the bar's.
                                    MouseArea {
                                        id: rowMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface1 }

            // --- footer -----------------------------------------------------
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Checked " + root.age(UpdateService.updatedAt)
                    color: Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                }

                Item { Layout.fillWidth: true }

                Text {
                    visible: root.count > 0
                    text: root.repo.length + " repo · " + root.aur.length + " AUR"
                    color: Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                }
            }
        }
    }
}
