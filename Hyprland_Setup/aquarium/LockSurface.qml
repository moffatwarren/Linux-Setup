import QtQuick
import Quickshell

// One monitor's lock screen: its own tank, with the clock and password box on top.
Item {
    id: root

    required property var context

    readonly property int px: tank.pixelSize
    readonly property color accent: context.checking ? "#f9e2af"
                                  : context.failure !== "" ? "#f38ba8" : "#585b70"

    // Ticks every second though it reads to the minute. A timer's clock stops during
    // suspend, so a minute-long tick could show the wrong time for up to a minute
    // after waking, which is the moment a lock screen is most likely to be looked at.
    // The string only changes once a minute, so the glyphs below rebuild no more often.
    readonly property string timeText: {
        const d = clock.date;
        const m = d.getMinutes();
        return (d.getHours() % 12 || 12) + ":" + (m < 10 ? "0" : "") + m
            + (d.getHours() < 12 ? "AM" : "PM");
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    Aquarium {
        id: tank
        anchors.fill: parent
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        cursorShape: root.context.awake ? Qt.ArrowCursor : Qt.BlankCursor
        onPositionChanged: root.context.poke()
        onPressed: {
            root.context.poke();
            input.forceActiveFocus();
        }
    }

    // Never seen: the dots below draw the password. It stays a real text field because
    // that is what handles keyboard layouts and dead keys correctly.
    TextInput {
        id: input

        width: 1
        height: 1
        opacity: 0
        focus: true
        readOnly: root.context.checking
        echoMode: TextInput.Password
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase

        onTextEdited: root.context.password = text

        Keys.onPressed: event => {
            root.context.poke();
            const ctrl = event.modifiers & Qt.ControlModifier;
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.context.submit();
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape
                       || (ctrl && (event.key === Qt.Key_U || event.key === Qt.Key_Backspace))) {
                root.context.password = "";
                event.accepted = true;
            }
        }

        // Only the monitor holding the keyboard is typed into; the others follow here.
        Connections {
            target: root.context
            function onPasswordChanged() {
                if (input.text !== root.context.password)
                    input.text = root.context.password;
            }
        }
    }

    Item {
        anchors.fill: parent
        opacity: root.context.awake ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 300 }
        }

        // Laid out in tank pixels, so it sits on the same pixel grid as the fish.
        Item {
            width: tank.tankWidth
            height: tank.tankHeight
            scale: root.px
            transformOrigin: Item.TopLeft

            // Fish swim behind this rather than through the digits: pastel fish are as
            // bright as the clock, and read as part of it. It is invisible on black water,
            // and it fades with the rest, so an idle screen has nothing in the way.
            Rectangle {
                readonly property int contentWidth: Math.max(clockRow.width, box.width)

                width: contentWidth + 14
                height: box.y + box.height + 12 - y
                x: Math.round((parent.width - width) / 2)
                y: clockRow.y - 4
                color: "black"
            }

            Row {
                id: clockRow
                x: Math.round((parent.width - width) / 2)
                y: Math.round(parent.height * 0.3)
                spacing: 3

                Repeater {
                    model: root.timeText.split("")
                    Image {
                        required property string modelData
                        source: tank.sprite("glyph_" + (modelData === ":" ? "colon" : modelData))
                        smooth: false
                    }
                }
            }

            // A faint outer border and a solid inner one.
            Rectangle {
                x: box.x - 1
                y: box.y - 1
                width: box.width + 2
                height: box.height + 2
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.3)
            }

            Rectangle {
                id: box

                width: 100
                height: 15
                x: Math.round((parent.width - width) / 2)
                y: clockRow.y + clockRow.height + 10
                color: "black"
                border.width: 1
                border.color: root.accent

                Row {
                    x: Math.round((parent.width - width) / 2)
                    y: 6
                    spacing: 2

                    Repeater {
                        model: Math.min(root.context.password.length, 18)
                        Rectangle {
                            width: 3
                            height: 3
                            color: root.context.checking ? "#f9e2af" : "#b4befe"
                        }
                    }
                }
            }
        }

        // Real text rather than glyphs, since PAM can say anything. It is outside the
        // scaled item above because scaling a Text up blurs it.
        Text {
            visible: root.context.password === "" && !root.context.checking
            anchors.horizontalCenter: parent.horizontalCenter
            y: (box.y + box.height / 2) * root.px - height / 2
            text: "Password"
            color: "#a6adc8"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 4 * root.px
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: (box.y + box.height + 5) * root.px
            text: root.context.checking ? "Checking..." : root.context.failure
            color: root.accent
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 4 * root.px
        }
    }
}
