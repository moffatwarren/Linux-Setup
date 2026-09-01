import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

// The popups, in place of swaync's floating notifications. Same frame as the
// bar's hover panels -- Theme.base inside a surface1 border, 14px radius, an
// urgency stripe down the leading edge -- because the swaync stylesheet was
// already built to look like them.
//
// Two shapes share the window:
//   * an ordinary notification: app icon, summary, body, action buttons.
//   * an OSD: the compact volume/brightness readout. It is a status readout
//     rather than a message, so it gets a small glyph, one line and a progress
//     bar, exactly as `.low` did in swaync/style.css.
//
// One window, following the focused monitor, rather than one per screen: two
// screens would otherwise each pop the same notification.
PanelWindow {
    id: root

    readonly property var popups: NotificationService.popups

    screen: {
        const name = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : "";
        const match = Quickshell.screens.filter(s => String(s.name) === name);
        return match.length > 0 ? match[0] : null;
    }

    anchors {
        top: true
        right: true
    }
    // Right margin matches Bar.qml's, so a card's right edge lines up with the
    // bar's. No top margin is needed to clear the bar itself: the bar reserves
    // an exclusive zone, so this surface already starts underneath it.
    margins {
        top: 6
        right: 5
    }

    implicitWidth: 380
    // Never zero -- a layer surface with no size is a protocol error, and the
    // window is hidden at that point anyway.
    implicitHeight: Math.max(1, column.implicitHeight)

    color: "transparent"
    visible: popups.length > 0
    // Reserve nothing (a popup must not push tiled windows around) but still
    // RESPECT the bar's own exclusive zone, which is what puts the first card
    // below the bar instead of on top of it. Not ExclusionMode.Ignore: that
    // means "ignore everyone else's zones" as well as "claim none", and draws
    // the toasts straight over the bar.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    // swaync's config.json had "layer": "overlay"; keep the same behaviour.
    WlrLayershell.layer: WlrLayer.Overlay

    Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 6

        Repeater {
            model: root.popups

            Rectangle {
                id: toast

                required property var modelData

                readonly property var notif: toast.modelData
                readonly property bool osd: NotificationService.isTransient(toast.notif)
                readonly property int progress: NotificationService.progressOf(toast.notif)
                readonly property color accent: NotificationService.accentFor(toast.notif.urgency)
                readonly property int timeout: NotificationService.timeoutFor(toast.notif)

                width: column.width
                implicitHeight: (toast.osd ? osdBody.implicitHeight : fullBody.implicitHeight) + 16
                radius: 14
                color: Theme.base
                border.width: 1
                // A critical notification tints its whole frame, not just the
                // stripe, the way the swaync sheet did.
                border.color: toast.notif.urgency === NotificationUrgency.Critical
                              ? Qt.rgba(toast.accent.r, toast.accent.g, toast.accent.b, 0.55)
                              : Theme.surface1

                // Fades in rather than snapping; swaync's transition-time was 200ms.
                // A one-shot, so the binding it replaces does not matter.
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                // A HoverHandler rather than the MouseArea's containsMouse: a
                // hovered child MouseArea (an action button, the close button)
                // takes the hover away from a MouseArea underneath it, which
                // would resume the timer while the pointer is still on the card
                // and, worse, hide the close button the moment it was aimed at.
                // A handler on the item keeps reporting for the whole subtree.
                HoverHandler { id: toastHover }

                // Hovering holds the toast open, so a notification cannot expire
                // out from under the pointer on its way to an action button.
                // Releasing the hover starts the full timeout again.
                Timer {
                    interval: Math.max(1, toast.timeout)
                    running: toast.timeout > 0 && !toastHover.hovered
                    onTriggered: NotificationService.hidePopup(toast.notif)
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 3
                    height: Math.max(14, parent.height - 16)
                    radius: 1.5
                    color: toast.accent
                }

                // --- an OSD -------------------------------------------------
                RowLayout {
                    id: osdBody
                    visible: toast.osd
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 15
                    anchors.rightMargin: 12
                    spacing: 10

                    // Drawn from the nerd font rather than the `-i` icon the
                    // script names. Those are Adwaita *-symbolic SVGs: GTK
                    // recoloured them from the stylesheet, but Qt renders them
                    // with the near-black fill baked into the file, which is
                    // invisible on this card. The glyphs are the same Material
                    // Design ones AudioPill draws, so the OSD and the bar agree.
                    Text {
                        text: {
                            const icon = String(toast.notif.appIcon ?? "");
                            if (icon.indexOf("brightness") !== -1) return "\udb81\udda8";   // sunny
                            if (icon.indexOf("muted") !== -1) return "\udb81\udf5f";        // volume-mute
                            if (icon.indexOf("headphone") !== -1 || icon.indexOf("headset") !== -1)
                                return "\udb80\udecb";                                      // headphones
                            if (icon.indexOf("volume-low") !== -1) return "\udb81\udd7f";
                            if (icon.indexOf("volume-medium") !== -1) return "\udb81\udd80";
                            return "\udb81\udd7e";                                          // volume-high
                        }
                        color: Theme.lavender
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 6
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            Layout.fillWidth: true
                            text: String(toast.notif.summary ?? "")
                            elide: Text.ElideRight
                            color: Theme.subtext1
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        // The int:value hint. Absent on "Volume Muted" and on
                        // the output-toggle popup, which have nothing to fill.
                        Rectangle {
                            Layout.fillWidth: true
                            visible: toast.progress >= 0
                            implicitHeight: 6
                            radius: 3
                            color: Theme.surface0

                            Rectangle {
                                width: parent.width * (toast.progress / 100)
                                height: parent.height
                                radius: parent.radius
                                color: Theme.blue

                                Behavior on width { NumberAnimation { duration: 100 } }
                            }
                        }
                    }
                }

                // --- an ordinary notification -------------------------------
                RowLayout {
                    id: fullBody
                    visible: !toast.osd
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 15
                    anchors.rightMargin: 12
                    spacing: 10

                    Item {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 2
                        implicitWidth: 40
                        implicitHeight: 40

                        Image {
                            id: art
                            anchors.fill: parent
                            visible: source != "" && status === Image.Ready
                            source: String(toast.notif.image ?? "")
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 80
                            sourceSize.height: 80
                            asynchronous: true
                        }

                        IconImage {
                            id: appIcon
                            anchors.fill: parent
                            visible: !art.visible && source != ""
                            asynchronous: true
                            source: {
                                const name = String(toast.notif.appIcon ?? "");
                                return name.length > 0 ? Quickshell.iconPath(name, true) : "";
                            }
                        }

                        // Nothing resolved -- an app that sent no icon, or one
                        // the icon theme does not have.
                        Text {
                            anchors.centerIn: parent
                            visible: !art.visible && !appIcon.visible
                            text: toast.notif.urgency === NotificationUrgency.Critical
                                  ? "\uf071"    // warning triangle
                                  : "\uf05a"    // info circle
                            color: toast.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: 26
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: String(toast.notif.appName ?? "")
                            elide: Text.ElideRight
                            color: toast.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 3
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: String(toast.notif.summary ?? "")
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 1
                            font.bold: true
                        }

                        Text {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            visible: text.length > 0
                            text: String(toast.notif.body ?? "")
                            textFormat: Text.StyledText
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            maximumLineCount: 4
                            color: Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        RowLayout {
                            Layout.topMargin: 6
                            spacing: 6
                            visible: toast.notif.actions.length > 0

                            Repeater {
                                model: toast.notif.actions

                                Rectangle {
                                    required property var modelData

                                    visible: String(modelData.identifier) !== "default"
                                    implicitWidth: actionLabel.implicitWidth + 20
                                    implicitHeight: 22
                                    radius: 10
                                    color: actionMouse.containsMouse ? Theme.surface1 : Theme.surface0
                                    border.width: 1
                                    border.color: Theme.surface1

                                    Text {
                                        id: actionLabel
                                        anchors.centerIn: parent
                                        text: String(modelData.text)
                                        color: actionMouse.containsMouse ? Theme.lavender : Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize - 2
                                    }

                                    MouseArea {
                                        id: actionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: modelData.invoke()
                                    }
                                }
                            }
                        }
                    }
                }

                // Close button, on hover. A critical notification never expires,
                // so there has to be something to press that is not "run the
                // app's default action".
                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 6
                    visible: !toast.osd && toastHover.hovered
                    implicitWidth: 18
                    implicitHeight: 18
                    radius: height / 2
                    color: closeMouse.containsMouse ? Theme.red : Theme.surface0

                    Text {
                        anchors.centerIn: parent
                        text: "\uf00d"
                        color: closeMouse.containsMouse ? Theme.crust : Theme.subtext0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotificationService.dismiss(toast.notif)
                    }
                }

                // Left-click runs the default action if the sender offered one
                // and clears the notification; right-click only hides the popup,
                // leaving it in the menu to deal with later.
                MouseArea {
                    id: toastMouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    // Under the action and close buttons, which have their own.
                    z: -1
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            NotificationService.hidePopup(toast.notif);
                            return;
                        }
                        const def = toast.notif.actions.find(a => String(a.identifier) === "default");
                        if (def) def.invoke();
                        NotificationService.dismiss(toast.notif);
                    }
                }
            }
        }
    }
}
