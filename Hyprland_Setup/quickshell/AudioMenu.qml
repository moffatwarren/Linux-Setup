import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

// Left-click dropdown on the audio module. Frame, anchoring and dismissal match
// BluetoothMenu; what it lists is different in one way worth stating up front.
//
// Outputs carry a SWITCH, not a radio button, because more than one can be on
// at once: the switches are the SUPER+O rotation, which
// hypr/scripts/audio-output-toggle.sh cycles. Clicking the row itself is what
// makes an output the default right now. Inputs carry a radio button, because
// there is only ever one default source.
//
// Only outputs that are plugged in are listed. AudioService remembers the
// switch of one that is not, so a headset comes back as it was left, but a row
// for it here would be a control with nothing to control -- SUPER+O cycles the
// present sinks, and can never land on an output that is not there.
//
// AudioService owns both the rotation and the file it persists to -- there is
// one of these menus per monitor and only one of them may write.
MenuPopup {
    id: root

    // The output whose icon palette is expanded, by sink name; "" for none.
    // Held here rather than per-delegate so opening one closes the last, and so
    // a delegate rebuilt by a model change does not silently reopen it.
    property string iconPickerFor: ""

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var sinkAudio: sink ? sink.audio : null
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sourceAudio: source ? source.audio : null

    // Wider than BluetoothMenu: sink descriptions run long ("Navi 48 HDMI/DP
    // Audio Controller Digital Stereo (HDMI 2) [27E3QKS]"), and a row here has
    // to fit a switch beside one.
    implicitWidth: 360
    implicitHeight: body.implicitHeight + 20

    // Overrides MenuPopup's, to drop the inline icon palette on the way out --
    // a function, unlike a signal handler, genuinely replaces the base's.
    function requestClose() { open = false; iconPickerFor = ""; }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.popupPad
        spacing: 5

        // --- header -----------------------------------------------------
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Audio"
                color: Theme.lavender
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            // The same mute the pill's right-click does, kept here as the
            // discoverable way to reach it -- the split BluetoothMenu uses
            // for the adapter.
            Text {
                text: {
                    if (!root.sinkAudio) return "\u2014";
                    return root.sinkAudio.muted
                        ? "muted" : Math.round(root.sinkAudio.volume * 100) + "%";
                }
                color: !root.sinkAudio ? Theme.overlay0
                     : root.sinkAudio.muted ? Theme.red : Theme.green
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.sinkAudio) root.sinkAudio.muted = !root.sinkAudio.muted
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface1 }

        // --- outputs ----------------------------------------------------
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Output"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }

            Item { Layout.fillWidth: true }

            Text {
                text: AudioService.enabledCount + " in SUPER+O"
                color: Theme.overlay0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }

        Repeater {
            model: AudioService.outputs

            // A Column, not the row itself, so the icon palette can drop in
            // underneath the output it belongs to.
            ColumnLayout {
                id: outItem

                required property var modelData

                readonly property bool isDefault: root.sink
                                                 && String(root.sink.name) === modelData.name

                Layout.fillWidth: true
                spacing: 2

                Rectangle {
                    id: outRow

                    readonly property var modelData: outItem.modelData
                    readonly property bool isDefault: outItem.isDefault

                    Layout.fillWidth: true
                    implicitHeight: 26
                    radius: 6
                    color: outMouse.containsMouse ? Theme.surface0 : "transparent"

                    // Under the switch, so clicking the switch never also
                    // changes the default output.
                    MouseArea {
                        id: outMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: AudioService.setDefaultSink(modelData.node)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 8

                        // The glyph doubles as the button that opens this
                        // output's icon palette -- there is nowhere else on a
                        // row this narrow to put one, and the thing you click
                        // is the thing you are changing.
                        Rectangle {
                            implicitWidth: 22
                            implicitHeight: 20
                            radius: 5
                            color: root.iconPickerFor === modelData.name ? Theme.surface1
                                 : iconMouse.containsMouse ? Theme.surface2 : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: AudioService.glyphFor(modelData.name)
                                color: outRow.isDefault ? Theme.green : Theme.subtext0
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                            }

                            MouseArea {
                                id: iconMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.iconPickerFor =
                                    root.iconPickerFor === modelData.name ? "" : modelData.name
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: modelData.description
                            elide: Text.ElideRight
                            color: outRow.isDefault ? Theme.green : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        // Whether this output is in the SUPER+O rotation. Same
                        // switch NotificationMenu draws for Do-not-disturb.
                        Rectangle {
                            implicitWidth: 30
                            implicitHeight: 16
                            radius: height / 2
                            color: modelData.enabled ? Theme.blue : Theme.surface1

                            Rectangle {
                                width: 12
                                height: 12
                                radius: height / 2
                                y: 2
                                x: modelData.enabled ? parent.width - width - 2 : 2
                                color: modelData.enabled ? Theme.crust : Theme.text

                                Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: AudioService.setEnabled(modelData.name, !modelData.enabled)
                            }
                        }
                    }
                }

                // --- the icon palette, under the output it belongs to --------
                // Which icon an output gets cannot be worked out from its name
                // (see AudioService.defaultIconKey), so it is asked once and
                // remembered. Laid out inline rather than as a popup: a second
                // layer-shell surface over a menu that already holds the
                // keyboard is a lot of machinery for six glyphs.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 2
                    visible: root.iconPickerFor === outItem.modelData.name
                    implicitHeight: visible ? 30 : 0
                    radius: 6
                    color: Theme.mantle

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        Repeater {
                            model: AudioService.iconChoices

                            Rectangle {
                                required property var modelData

                                readonly property bool picked:
                                    AudioService.iconKey(outItem.modelData.name) === modelData.key

                                implicitWidth: 30
                                implicitHeight: 22
                                radius: 5
                                color: picked ? Theme.surface1
                                     : choiceMouse.containsMouse ? Theme.surface0 : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.glyph
                                    color: parent.picked ? Theme.blue : Theme.subtext0
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                }

                                MouseArea {
                                    id: choiceMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        AudioService.setIcon(outItem.modelData.name, modelData.key);
                                        root.iconPickerFor = "";
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: AudioService.outputs.length === 0
            text: "No outputs"
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        // --- inputs -----------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 3

            Text {
                text: "Input"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }

            Item { Layout.fillWidth: true }

            Text {
                text: {
                    if (!root.sourceAudio) return "\u2014";
                    return root.sourceAudio.muted
                        ? "muted" : Math.round(root.sourceAudio.volume * 100) + "%";
                }
                color: !root.sourceAudio ? Theme.overlay0
                     : root.sourceAudio.muted ? Theme.red : Theme.green
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.sourceAudio) root.sourceAudio.muted = !root.sourceAudio.muted
                }
            }
        }

        Repeater {
            model: AudioService.sources

            Rectangle {
                id: inRow

                required property var modelData

                readonly property bool isDefault: root.source
                                                  && String(root.source.name) === String(modelData.name)

                Layout.fillWidth: true
                implicitHeight: 26
                radius: 6
                color: inMouse.containsMouse ? Theme.surface0 : "transparent"

                MouseArea {
                    id: inMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: AudioService.setDefaultSource(modelData)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 8

                    // Only one input can be the default, so this is a radio
                    // button rather than the outputs' switch.
                    Rectangle {
                        implicitWidth: 16
                        implicitHeight: 16
                        radius: height / 2
                        color: inRow.isDefault ? Theme.blue : Theme.surface1
                        border.width: 1
                        border.color: inRow.isDefault ? Theme.blue : Theme.overlay0

                        Rectangle {
                            anchors.centerIn: parent
                            width: 8
                            height: 8
                            radius: height / 2
                            visible: inRow.isDefault
                            color: Theme.crust
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: AudioService.nodeLabel(modelData)
                        elide: Text.ElideRight
                        color: inRow.isDefault ? Theme.green : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    // Mic mute toggle button for this input source
                    Rectangle {
                        implicitWidth: 22
                        implicitHeight: 20
                        radius: 5
                        color: micBtnMouse.containsMouse ? Theme.surface1 : "transparent"

                        Text {
                            anchors.centerIn: parent
                            readonly property bool isMuted: modelData.audio ? modelData.audio.muted : false
                            text: isMuted ? "\udb80\udf6d" : "\udb80\udf6c"
                            color: isMuted ? Theme.red : (inRow.isDefault ? Theme.green : Theme.subtext0)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        MouseArea {
                            id: micBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.audio) {
                                    modelData.audio.muted = !modelData.audio.muted;
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: AudioService.sources.length === 0
            text: "No inputs"
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface1 }

        Text {
            text: "Open pavucontrol\u2026"
            color: pavuMouse.containsMouse ? Theme.lavender : Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2

            MouseArea {
                id: pavuMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Quickshell.execDetached(["pavucontrol"]);
                    root.requestClose();
                }
            }
        }
    }
}
