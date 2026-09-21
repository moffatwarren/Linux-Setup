import QtQuick

// The volume track AudioMenu puts in its Output and Input headers.
//
// Drawn by hand like the switch and the radio button beside it rather than
// taken from QtQuick.Controls: nothing else in this bar imports Controls, and a
// styled Slider would be more machinery than a track, a fill and a handle.
//
// It drives a PwNodeAudio directly -- the same object AudioPill's scroll wheel
// writes to -- so there is no state here to fall out of step with the node.
Item {
    id: root

    // A PwNodeAudio, or null while nothing is default. Null is drawn as an
    // empty track rather than hidden, so the header does not change shape when
    // a sink comes and goes.
    property var audio: null
    property color accent: Theme.blue

    readonly property bool muted: audio ? audio.muted : false
    // PipeWire allows over-amplification; the track only ever draws 0..100%.
    readonly property real value: audio ? Math.max(0, Math.min(1, audio.volume)) : 0

    readonly property int handleSize: 12
    // The handle's centre travels this span, so the fill and the handle agree
    // about where a given percentage is.
    readonly property real span: Math.max(1, width - handleSize)

    implicitWidth: 110
    implicitHeight: 18
    opacity: audio ? 1 : 0.5

    // Unmutes, the way AudioPill's wheel does: a slider that moves and makes no
    // sound reads as a broken slider, and the percentage next to it is the mute
    // toggle for when muting is what was wanted.
    function setFromX(x) {
        if (!audio) return;
        audio.muted = false;
        audio.volume = Math.max(0, Math.min(1, (x - handleSize / 2) / span));
    }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.handleSize / 2
        anchors.rightMargin: root.handleSize / 2
        implicitHeight: 4
        radius: height / 2
        color: Theme.surface1

        Rectangle {
            width: track.width * root.value
            height: parent.height
            radius: parent.radius
            color: root.muted ? Theme.overlay0 : root.accent
        }
    }

    Rectangle {
        width: root.handleSize
        height: root.handleSize
        radius: height / 2
        x: root.span * root.value
        anchors.verticalCenter: parent.verticalCenter
        color: root.muted ? Theme.overlay0 : root.accent
        border.width: 1
        border.color: Theme.crust
        scale: drag.pressed ? 1.25 : drag.containsMouse ? 1.15 : 1

        Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: drag

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.audio !== null
        cursorShape: Qt.PointingHandCursor
        // The menu's rows sit directly under this; without it a drag that
        // strays vertically is taken over by whatever is beneath.
        preventStealing: true

        onPressed: mouse => root.setFromX(mouse.x)
        onPositionChanged: mouse => { if (pressed) root.setFromX(mouse.x); }

        // 1% a notch, matching AudioPill's wheel and the
        // XF86AudioRaise/LowerVolume keys (`wpctl set-volume … 1%+`).
        onWheel: wheel => {
            if (!root.audio) return;
            root.audio.muted = false;
            root.audio.volume = Math.max(0, Math.min(1,
                root.audio.volume + (wheel.angleDelta.y > 0 ? 0.01 : -0.01)));
        }
    }
}
