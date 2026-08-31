import QtQuick

// A rounded module pill: matches style.css (radius 15, alpha(@surface0,0.85),
// 0.2rem 1rem padding). Hidden automatically when it has no text, which is how
// modules with nothing to report (no battery, no media) drop out of the bar.
Rectangle {
    id: root

    property string label: ""
    // Lets modules drive a hover popup without another MouseArea.
    readonly property alias hovered: mouse.containsMouse
    property color labelColor: Theme.text
    // StyledText lets a module colour just part of its label,
    // e.g. only the on/off word rather than the whole pill.
    property bool richText: false

    signal clicked
    signal doubleClicked
    signal rightClicked
    signal scrolled(int delta)

    visible: label.length > 0
    implicitWidth: text.implicitWidth + Theme.pillPad * 2
    implicitHeight: Theme.pillHeight
    radius: height / 2
    color: Theme.pill

    Text {
        id: text
        anchors.centerIn: parent
        text: root.label
        color: root.labelColor
        textFormat: root.richText ? Text.StyledText : Text.PlainText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) root.rightClicked();
            else root.clicked();
        }
        onDoubleClicked: root.doubleClicked()
        onWheel: wheel => root.scrolled(wheel.angleDelta.y)
    }
}
