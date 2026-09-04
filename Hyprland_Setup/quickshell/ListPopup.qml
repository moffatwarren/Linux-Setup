import Quickshell
import QtQuick
import QtQuick.Layouts

// Catppuccin-styled hover panel used in place of the stock QtQuick tooltips,
// which ignored the palette entirely. Shows a title and a list of
// { text, detail, accent } rows, right-aligning the detail column.
//
// It wears MenuPopup's frame, so it hangs off the bar exactly as a menu does,
// but it does not own its `open`: that is derived from `requested` below and so
// must never be assigned to. Hence closeOnDismiss false and the requestClose
// override -- the client owns the flag and does the actual closing.
MenuPopup {
    id: root

    property bool requested: false
    property string title: ""
    property var rows: []
    property string emptyText: ""
    // Optional cap on the right-hand column, for rows whose detail is a device
    // name long enough to stretch the panel across the screen. 0 = no cap.
    property int maxDetailWidth: 0
    property int delayMs: 300
    // Opt-in, for a client that opens this on a click rather than on hover.
    // A hover panel is dismissed by moving the pointer, so it needs none of
    // this; one you opened deliberately has to close deliberately, which means
    // Escape and a click anywhere outside -- and a layer-shell surface gets no
    // event for an outside click on its own. Off by default, so the modules
    // that still hover (recorder, updates) are untouched.
    property bool dismissable: false

    readonly property bool hasContent: rows.length > 0 || emptyText.length > 0

    implicitWidth: body.implicitWidth + 24
    implicitHeight: body.implicitHeight + 20

    // Bound rather than set imperatively: an onRequestedChanged handler never
    // fires when `requested` is already true at construction.
    property bool delayPassed: false
    open: requested && hasContent && delayPassed

    // A hover panel must never take the keyboard -- it would hold it for as
    // long as the pointer crossed the pill. `dismissable` is what turns on the
    // focus grab, the Escape handler and the outside-click dismissal together.
    grabsFocus: dismissable
    // The client owns the flag behind `requested`, so it does the closing; this
    // only reports. Assigning `open` here would destroy the binding above.
    closeOnDismiss: false
    function requestClose() { root.dismissed(); }

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
