import QtQuick

// One animated pixel-art sprite. Every frame is its own always-loaded Image and
// only `visible` changes, so swapping frames re-reads nothing and uploads nothing:
// changing an Image's `source` instead would go back through the pixmap cache on
// every tail flick.
Item {
    id: root

    property string name
    property int frames: 1
    property int frame: 0
    property bool flip: false

    readonly property string stem: Qt.resolvedUrl("sprites/" + name)

    implicitWidth: first.implicitWidth
    implicitHeight: first.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Image {
        id: first
        source: root.frames > 1 ? root.stem + "_0.png" : root.stem + ".png"
        visible: root.frame === 0
        mirror: root.flip
        smooth: false
    }

    Repeater {
        model: root.frames - 1
        Image {
            required property int index
            source: root.stem + "_" + (index + 1) + ".png"
            visible: root.frame === index + 1
            mirror: root.flip
            smooth: false
        }
    }
}
