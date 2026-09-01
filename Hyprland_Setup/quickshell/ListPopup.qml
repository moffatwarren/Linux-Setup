import Quickshell
import QtQuick
import QtQuick.Layouts

// Catppuccin-styled hover panel used in place of the stock QtQuick tooltips,
// which ignored the palette entirely. Shows a title and a list of
// { text, detail, accent } rows, right-aligning the detail column.
PopupWindow {
    id: root

    property Item anchorItem: null
    property bool requested: false
    property string title: ""
    property var rows: []
    property string emptyText: ""
    // Optional cap on the right-hand column, for rows whose detail is a device
    // name long enough to stretch the panel across the screen. 0 = no cap.
    property int maxDetailWidth: 0
    property int delayMs: 300

    readonly property bool hasContent: rows.length > 0 || emptyText.length > 0

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 6

    implicitWidth: body.implicitWidth + 24
    implicitHeight: body.implicitHeight + 20
    color: "transparent"
    // Bound rather than set imperatively: an onRequestedChanged handler never
    // fires when `requested` is already true at construction.
    property bool delayPassed: false
    visible: requested && hasContent && delayPassed

    onRequestedChanged: {
        if (requested) openTimer.restart();
        else { openTimer.stop(); delayPassed = false; }
    }
    Component.onCompleted: if (requested) openTimer.restart()

    Timer {
        id: openTimer
        interval: root.delayMs
        onTriggered: root.delayPassed = true
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.base
        border.width: 1
        border.color: Theme.surface1

        ColumnLayout {
            id: body
            anchors.centerIn: parent
            spacing: 5

            Text {
                text: root.title
                visible: root.title.length > 0
                color: Theme.lavender
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.title.length > 0 && root.rows.length > 0
                implicitHeight: 1
                color: Theme.surface1
            }

            Text {
                text: root.emptyText
                visible: root.rows.length === 0 && root.emptyText.length > 0
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Repeater {
                model: root.rows

                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 16

                    Text {
                        text: modelData.text
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: modelData.detail !== undefined ? modelData.detail : ""
                        color: modelData.accent !== undefined ? modelData.accent : Theme.subtext0
                        Layout.maximumWidth: root.maxDetailWidth > 0
                                             ? root.maxDetailWidth : Number.POSITIVE_INFINITY
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }
            }
        }
    }
}
