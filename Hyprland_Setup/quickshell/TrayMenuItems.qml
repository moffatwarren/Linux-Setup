import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// One level of an app's DBus menu, and -- via the Loader at the bottom -- every
// level below it. Submenus expand inline and indented rather than flying out
// sideways: a flyout is a second layer-shell surface with its own focus grab,
// and two grabs fighting is exactly what the WifiMenu password field already
// cost to get right.
ColumnLayout {
    id: root

    // A QsMenuHandle: either a tray item's root menu, or an entry with
    // children. Null closes the menu on the app's side.
    property var handle: null
    property int depth: 0

    // Bubbles up to TrayMenu, which closes the whole thing. Only a leaf entry
    // emits it -- expanding a submenu must leave the menu open.
    signal activated

    spacing: 2

    // Checkbox and radio marks, as \uXXXX escapes -- a private-use codepoint
    // pasted literally comes through as an empty string (see CLAUDE.md).
    function markGlyph(item) {
        const on = item.checkState === Qt.Checked;
        if (item.buttonType === QsMenuButtonType.RadioButton)
            return on ? "\uf192" : "\uf10c";   // dot-circle-o / circle-o
        return on ? "\uf14a" : "\uf096";       // check-square-o / square-o
    }

    QsMenuOpener {
        id: opener
        menu: root.handle
    }

    Repeater {
        model: opener.children.values

        ColumnLayout {
            id: entry

            required property var modelData

            Layout.fillWidth: true
            spacing: 2

            property bool expanded: false

            Rectangle {
                visible: entry.modelData.isSeparator
                Layout.fillWidth: true
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                Layout.topMargin: 2
                Layout.bottomMargin: 2
                implicitHeight: 1
                color: Theme.surface1
            }

            Rectangle {
                visible: !entry.modelData.isSeparator
                Layout.fillWidth: true
                implicitHeight: 24
                radius: 6
                color: rowMouse.containsMouse && entry.modelData.enabled
                       ? Theme.surface0 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    // Indent per level, so a nested entry reads as belonging to
                    // the row above it.
                    anchors.leftMargin: 6 + root.depth * 12
                    anchors.rightMargin: 6
                    spacing: 8

                    // Checkbox / radio state. The slot is reserved whether or
                    // not this entry is checkable, so labels in a menu that
                    // mixes both still line up.
                    Item {
                        visible: entry.modelData.buttonType !== QsMenuButtonType.None
                        implicitWidth: 12
                        implicitHeight: 12

                        Text {
                            anchors.centerIn: parent
                            text: root.markGlyph(entry.modelData)
                            color: entry.modelData.checkState === Qt.Checked
                                   ? Theme.green : Theme.overlay0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }
                    }

                    IconImage {
                        implicitWidth: 14
                        implicitHeight: 14
                        source: String(entry.modelData.icon ?? "")
                        asynchronous: true
                        visible: source != "" && status !== Image.Error
                    }

                    Text {
                        Layout.fillWidth: true
                        text: String(entry.modelData.text ?? "")
                        elide: Text.ElideRight
                        color: entry.modelData.enabled ? Theme.text : Theme.overlay0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    Text {
                        visible: entry.modelData.hasChildren
                        text: entry.expanded ? "\uf078" : "\uf054"   // chevron down / right
                        color: Theme.subtext0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 4
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: entry.modelData.enabled
                    onClicked: {
                        if (entry.modelData.hasChildren) {
                            entry.expanded = !entry.expanded;
                            return;
                        }
                        entry.modelData.triggered();
                        root.activated();
                    }
                }
            }

            Loader {
                Layout.fillWidth: true
                active: entry.expanded && entry.modelData.hasChildren
                // Loaded by URL rather than named as a type: a QML file that
                // instantiates itself is a cyclic dependency at compile time,
                // and a DBus menu nests as deep as the app wants it to.
                source: "TrayMenuItems.qml"
                onLoaded: {
                    item.handle = entry.modelData;
                    item.depth = root.depth + 1;
                    item.activated.connect(root.activated);
                }
            }
        }
    }
}
