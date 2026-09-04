import QtQuick

// A rounded module pill: matches style.css (radius 15, alpha(@surface0,0.85),
// 0.2rem 1rem padding). Hidden automatically when it has no text, which is how
// modules with nothing to report (no battery, no media) drop out of the bar.
Rectangle {
    id: root

    property string label: ""
    // A module that draws its own content instead of a label (TailscalePill's
    // logo) overrides these two: `hasContent` is what decides whether the
    // module is in the bar at all, and `contentWidth` is what the pill sizes
    // to. Their defaults are the label, so a text module needs neither.
    // Not named `active`: NetworkPill already uses that for its active device,
    // and one object carrying two unrelated `active`s is a trap even though
    // the shadowing is harmless (verified: a derived property of the same name
    // does not capture the base's own `visible` binding).
    property bool hasContent: label.length > 0
    property real contentWidth: -1
    // Lets modules drive a hover popup without another MouseArea.
    readonly property alias hovered: mouse.containsMouse
    property color labelColor: Theme.text
    // StyledText lets a module colour just part of its label,
    // e.g. only the on/off word rather than the whole pill.
    property bool richText: false

    // The drop-down this module owns, if it has one. Setting it is what turns
    // on both the open highlight and the hover hand-off below.
    property MenuPopup menu: null
    readonly property bool menuOpen: menu ? menu.open : false

    // "Open my menu" -- called by the click AND by the hand-off, so a module
    // with side effects on opening (NetworkPill fetches its public IP,
    // PowerProfilePill takes an immediate stats reading) defines them once
    // instead of having the two paths drift apart. Overridden where the menu's
    // `open` is not this module's to write.
    property var openMenu: () => { if (root.menu) root.menu.open = true; }

    // True when a hover here would actually switch menus -- i.e. some OTHER
    // module's drop-down is up. Nothing on this bar reacted to hover before, so
    // the tint is what makes the gesture discoverable.
    readonly property bool handoffTarget: menu !== null
                                          && MenuService.current !== null
                                          && MenuService.current !== menu

    signal clicked
    signal doubleClicked
    signal rightClicked
    signal scrolled(int delta)

    visible: hasContent
    implicitWidth: (contentWidth >= 0 ? contentWidth : text.implicitWidth) + Theme.pillPad * 2
    implicitHeight: Theme.pillHeight
    radius: height / 2
    color: menuOpen || (hovered && handoffTarget) ? Theme.surface0 : Theme.pill

    Behavior on color {
        ColorAnimation { duration: 100; easing.type: Easing.OutCubic }
    }

    // With a menu already open, crossing another module switches to its menu,
    // the way a menubar does. The delay is the whole reason this is a Timer:
    // without it, sweeping the pointer along the bar strobes every menu it
    // passes over on the way to somewhere else.
    Timer {
        id: handoff
        interval: 90
        onTriggered: root.openMenu()
    }

    onHoveredChanged: {
        if (root.hovered && root.handoffTarget) handoff.restart();
        else handoff.stop();
    }

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
