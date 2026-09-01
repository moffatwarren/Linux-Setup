pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

// The shared frame behind every full-screen overlay: the SUPER+W wallpaper
// picker, the SUPER+SPACE app launcher and the SUPER+V clipboard history.
//
// All three are the same window -- dimmed backdrop, a centred `base` card in a
// surface1 border, a lavender title with a filter box under it and a hint line
// along the bottom -- so they read as one family rather than as three
// unrelated menus that happen to share a palette. Only the body differs: a
// filmstrip of thumbnails, a list of apps, a list of clipboard entries.
//
// Geometry lives here for the same reason the colours do. The panel's padding,
// header height and the gaps around the body are what make two overlays look
// alike; if each one carried its own copy they would drift apart the first
// time one of them was adjusted.
//
// Children go in the body. They are declared in the *consumer's* file, so they
// can freely reference that file's ids (including its root OverlayPanel).
PanelWindow {
    id: root

    property bool open: false

    // Header. `subtitle` is the changing text beside the title (a filename, an
    // app's description); `countLabel` sits at the right edge.
    property string title: ""
    property string subtitle: ""
    property string countLabel: ""
    // Drawn in the filter box while it is empty.
    property string placeholder: ""
    // The hint line under the body. `footerColor` lets a consumer turn it red
    // to report "nothing matches".
    property string footerText: ""
    property color footerColor: Theme.overlay0

    property int panelWidth: 640
    // The height of the body area; the window sizes itself around it.
    property int bodyHeight: 400

    readonly property alias filterText: filterInput.text

    default property alias content: body.data

    // Emitted after show() has reset the filter -- refresh data and put the
    // cursor somewhere sensible here.
    signal opened
    // Enter/Return in the filter box.
    signal accepted
    // Any other key the filter box did not claim first. Set `event.accepted`
    // on the ones the body handles (arrows, PageUp, ...); anything left
    // unaccepted falls through and types into the filter box.
    signal navKey(var event)

    // Follow the focused monitor, so the overlay opens where you are looking.
    screen: Hyprland.focusedMonitor?.screen ?? null

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-overlay"
    // Exclusive, not OnDemand: these are opened by a keybind, so there is no
    // click to hand the surface the keyboard first.
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive
                                           : WlrKeyboardFocus.None

    function toggle(): void {
        if (root.open) root.close();
        else root.show();
    }

    function show(): void {
        filterInput.text = "";
        root.open = true;
        root.opened();
        // The window is not mapped yet on the same tick as `open`, so the
        // keyboard grab has nothing to hand focus to until after this returns.
        Qt.callLater(() => filterInput.forceActiveFocus());
    }

    function close(): void {
        root.open = false;
    }

    // Dim whatever is on screen; clicking it is the mouse equivalent of Escape.
    Rectangle {
        anchors.fill: parent
        color: "#cc11111b"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Rectangle {
        id: panel

        readonly property int pad: 18

        anchors.centerIn: parent
        width: root.panelWidth
        // 26 = the 14px gap above the body plus the 12px above the footer.
        height: header.height + root.bodyHeight + footer.height + panel.pad * 2 + 26
        radius: 16
        color: Theme.base
        border.width: 1
        border.color: Theme.surface1

        // Swallow clicks so they do not reach the dismiss layer underneath.
        MouseArea { anchors.fill: parent }

        Item {
            id: header

            anchors { top: parent.top; left: parent.left; right: parent.right; margins: panel.pad }
            height: 58

            Text {
                id: titleText
                anchors.left: parent.left
                anchors.top: parent.top
                text: root.title
                color: Theme.lavender
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 4
                font.bold: true
            }

            Text {
                anchors.left: titleText.right
                anchors.leftMargin: 14
                anchors.right: countText.left
                anchors.rightMargin: 14
                anchors.baseline: titleText.baseline
                text: root.subtitle
                color: Theme.subtext0
                elide: Text.ElideMiddle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                id: countText
                anchors.right: parent.right
                anchors.baseline: titleText.baseline
                text: root.countLabel
                color: Theme.overlay0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 30
                radius: 8
                color: Theme.surface0

                Text {
                    id: prompt
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    // Written as an escape: nerd font glyphs are private-use
                    // codepoints and pasting them literally yields an empty string.
                    text: "\uf002" // nf-fa-search
                    color: Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                // A real TextInput rather than accumulating event.text by hand,
                // so backspace, selection and paste all work. The navigation
                // keys are intercepted below before it can move its cursor.
                TextInput {
                    id: filterInput

                    anchors { left: prompt.right; right: parent.right; verticalCenter: parent.verticalCenter }
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    focus: true
                    color: Theme.text
                    selectionColor: Theme.surface2
                    selectedTextColor: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize

                    Text {
                        anchors.fill: parent
                        visible: filterInput.text.length === 0
                        text: root.placeholder
                        color: Theme.overlay0
                        verticalAlignment: Text.AlignVCenter
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Escape:
                            root.close();
                            event.accepted = true;
                            return;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.accepted();
                            event.accepted = true;
                            return;
                        }
                        // Anything the body does not claim types into the box.
                        root.navKey(event);
                    }
                }
            }
        }

        Item {
            id: body

            anchors {
                top: header.bottom
                topMargin: 14
                left: parent.left
                right: parent.right
                leftMargin: panel.pad
                rightMargin: panel.pad
            }
            height: root.bodyHeight
        }

        Text {
            id: footer

            anchors { left: parent.left; right: parent.right; top: body.bottom }
            anchors.leftMargin: panel.pad
            anchors.rightMargin: panel.pad
            anchors.topMargin: 12
            height: 16
            text: root.footerText
            color: root.footerColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }
}
