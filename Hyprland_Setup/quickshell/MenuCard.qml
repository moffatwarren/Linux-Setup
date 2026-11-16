import QtQuick
import QtQuick.Layouts

// One section of a drop-down that has more than one: a recessed `mantle` card
// inside the menu's `base` frame. ClockMenu stacks three of them.
//
// Mantle rather than a lighter surface because the cards' own controls -- the
// calendar's arrows, the forecast's Refresh chip -- hover and fill in
// `surface0`, which would vanish on a surface0 card.
//
// Children land in a ColumnLayout, so a card's body is laid out the way every
// other menu body here is.
Rectangle {
    id: root

    default property alias content: column.data
    property int padding: 12
    property int spacing: 6

    color: Theme.mantle
    radius: Theme.popupRadius
    border.width: Theme.borderWidth
    border.color: Theme.surface0

    implicitWidth: column.implicitWidth + 2 * root.padding
    implicitHeight: column.implicitHeight + 2 * root.padding

    ColumnLayout {
        id: column
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: root.spacing
    }
}
