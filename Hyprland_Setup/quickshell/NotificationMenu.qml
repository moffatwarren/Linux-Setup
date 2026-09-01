pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

// The notification centre, in place of swaync's control panel: everything that
// has arrived and not been dismissed, plus the mute toggle.
//
// Frame, anchoring and dismissal match PowerMenu, WifiMenu and TrayMenu --
// Theme.base inside a surface1 border, Escape or a click outside to close.
//
// `open` is driven from NotificationService.menuMonitor rather than owned here,
// because there is one bar (and one of these) per monitor and SUPER+N must open
// exactly one of them.
PopupWindow {
    id: root

    property Item anchorItem: null
    property bool open: false

    readonly property var entries: NotificationService.entries

    // Re-rendered on a timer so "2 min" does not sit there lying; only while the
    // menu is actually on screen.
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

    function close() { NotificationService.closeMenu(); }

    onOpenChanged: if (open) root.now = Date.now()

    Timer {
        running: root.open
        interval: 30000
        repeat: true
        onTriggered: root.now = Date.now()
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
                    text: "Notifications"
                    color: Theme.lavender
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Text {
                    visible: root.entries.length > 0
                    text: root.entries.length
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface1 }

            // --- mute toggle ------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 30
                radius: 8
                color: dndMouse.containsMouse ? Theme.surface0 : Theme.mantle

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 8

                    Text {
                        // bell-slash when muted, bell when not.
                        text: NotificationService.dnd ? "\uf1f6" : "\uf0f3"
                        color: NotificationService.dnd ? Theme.red : Theme.subtext0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Do not disturb"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    // Mirrors the GTK switch swaync's DND widget used to draw.
                    Rectangle {
                        implicitWidth: 34
                        implicitHeight: 18
                        radius: height / 2
                        color: NotificationService.dnd ? Theme.blue : Theme.surface1

                        Rectangle {
                            width: 14
                            height: 14
                            radius: height / 2
                            y: 2
                            x: NotificationService.dnd ? parent.width - width - 2 : 2
                            color: NotificationService.dnd ? Theme.crust : Theme.text

                            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }
                    }
                }

                MouseArea {
                    id: dndMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.toggleDnd()
                }
            }

            // --- empty state ------------------------------------------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                visible: root.entries.length === 0
                spacing: 6

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "\uf0a2"                // bell, outline
                    color: Theme.surface2
                    font.family: Theme.fontFamily
                    font.pixelSize: 30
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No notifications"
                    color: Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }

            // --- the list ---------------------------------------------------
            // Capped and clipped rather than allowed to grow: a busy morning
            // should not produce a menu taller than the screen. Scrolls on the
            // wheel; no scrollbar, matching the rest of the bar's popups.
            ListView {
                id: list

                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 420)
                visible: root.entries.length > 0
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: root.entries

                delegate: Rectangle {
                    id: card

                    required property var modelData

                    readonly property var notif: card.modelData.n
                    readonly property color accent: NotificationService.accentFor(card.notif.urgency)

                    width: list.width
                    implicitHeight: cardBody.implicitHeight + 16
                    radius: 10
                    color: cardHover.hovered ? Theme.surface0 : Theme.mantle

                    // A handler, not the MouseArea's containsMouse: hovering an
                    // action button would otherwise take the hover off the card
                    // underneath it and drop the highlight.
                    HoverHandler { id: cardHover }

                    // Urgency as a stripe down the leading edge, as the swaync
                    // stylesheet drew it -- inset with rounded ends rather than a
                    // full-height border, so it does not fight the card's corners.
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: Math.max(14, parent.height - 16)
                        radius: 1.5
                        color: card.accent
                    }

                    RowLayout {
                        id: cardBody
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 15
                        anchors.rightMargin: 10
                        spacing: 9

                        // The image hint (album art, a screenshot) when there is
                        // one, otherwise the sending app's icon.
                        Item {
                            Layout.alignment: Qt.AlignTop
                            Layout.topMargin: 1
                            implicitWidth: 30
                            implicitHeight: 30
                            visible: art.visible || appIcon.visible

                            Image {
                                id: art
                                anchors.fill: parent
                                visible: source != "" && status === Image.Ready
                                source: String(card.notif.image ?? "")
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 60
                                sourceSize.height: 60
                                asynchronous: true
                            }

                            IconImage {
                                id: appIcon
                                anchors.fill: parent
                                visible: !art.visible && source != ""
                                asynchronous: true
                                source: {
                                    const name = String(card.notif.appIcon ?? "");
                                    if (name.length === 0) return "";
                                    return Quickshell.iconPath(name, true);
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    Layout.fillWidth: true
                                    text: String(card.notif.appName ?? "")
                                    elide: Text.ElideRight
                                    color: card.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                }

                                Text {
                                    text: NotificationService.ago(card.modelData.time, root.now)
                                    color: Theme.overlay0
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text.length > 0
                                text: String(card.notif.summary ?? "")
                                elide: Text.ElideRight
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 1
                                visible: text.length > 0
                                text: String(card.notif.body ?? "")
                                // Apps may send Pango markup; the server
                                // advertises bodyMarkup, so honour it.
                                textFormat: Text.StyledText
                                wrapMode: Text.Wrap
                                elide: Text.ElideRight
                                maximumLineCount: 3
                                color: Theme.subtext0
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }

                            // --- action buttons ---------------------------
                            // "default" is what a click on the card itself
                            // invokes, so it is not given a button of its own.
                            RowLayout {
                                Layout.topMargin: 4
                                spacing: 6
                                visible: card.notif.actions.length > 0

                                Repeater {
                                    model: card.notif.actions

                                    Rectangle {
                                        required property var modelData

                                        visible: String(modelData.identifier) !== "default"
                                        implicitWidth: actionLabel.implicitWidth + 16
                                        implicitHeight: 20
                                        radius: 8
                                        color: actionMouse.containsMouse ? Theme.surface1 : Theme.surface0
                                        border.width: 1
                                        border.color: Theme.surface1

                                        Text {
                                            id: actionLabel
                                            anchors.centerIn: parent
                                            text: String(modelData.text)
                                            color: actionMouse.containsMouse ? Theme.lavender : Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 3
                                        }

                                        MouseArea {
                                            id: actionMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                modelData.invoke();
                                                root.close();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Left-click runs the notification's default action (if it
                    // has one) and clears it; right-click just clears it --
                    // the same split ClipboardMenu uses for its rows.
                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // Sits under the action buttons, which have their own.
                        z: -1
                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton) {
                                const def = card.notif.actions.find(a => String(a.identifier) === "default");
                                if (def) {
                                    def.invoke();
                                    root.close();
                                    return;
                                }
                            }
                            NotificationService.dismiss(card.notif);
                        }
                    }
                }
            }

            // --- footer -----------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                visible: root.entries.length > 0
                implicitHeight: 1
                color: Theme.surface1
            }

            Text {
                visible: root.entries.length > 0
                text: "\uf1f8  Clear all"       // trash
                color: clearMouse.containsMouse ? Theme.red : Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2

                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.clearAll()
                }
            }
        }
    }
}
