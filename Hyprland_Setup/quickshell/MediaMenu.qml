import Quickshell
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// Transport controls for the media module: the album art at a size worth
// looking at, the track above previous / play-pause / next.
// Opened by clicking the album art or the title (MediaGroup), rather than
// hanging playback on a click and a skip on a double-click -- which meant
// every skip also toggled playback on the way through.
//
// Frame, anchoring and dismissal match PowerMenu and BluetoothMenu.
MenuPopup {
    id: root

    // The MprisPlayer MediaGroup picked; null when nothing is playing.
    property var player: null

    readonly property string title: player && player.trackTitle ? String(player.trackTitle) : ""
    readonly property string artist: player && player.trackArtist ? String(player.trackArtist) : ""
    readonly property string artUrl: player && player.trackArtUrl ? String(player.trackArtUrl) : ""
    readonly property bool playing: player !== null && player.isPlaying

    implicitWidth: 230
    implicitHeight: body.implicitHeight + 20

    // The module hides itself when nothing is playing; a menu left open would
    // otherwise hang off an invisible anchor with dead buttons.
    onPlayerChanged: if (player === null) requestClose();

    // Space is play/pause while this menu is up -- the transport control you
    // reach for without aiming at a button. Accepted either way, so it cannot
    // fall through to anything else; togglePlay() is already a no-op for a
    // player that says it cannot be toggled.
    onKeyPressed: event => {
        if (event.key === Qt.Key_Space) {
            root.togglePlay();
            event.accepted = true;
        }
    }

    function previousTrack() {
        if (player && player.canGoPrevious) player.previous();
    }

    function togglePlay() {
        if (player && player.canTogglePlaying) player.togglePlaying();
    }

    function nextTrack() {
        if (player && player.canGoNext) player.next();
    }

    function formatTime(seconds: real): string {
        if (isNaN(seconds) || seconds < 0) return "0:00";
        const s = seconds > 100000 ? Math.floor(seconds / 1000000) : Math.floor(seconds);
        const m = Math.floor(s / 60);
        const sec = s % 60;
        return m + ":" + (sec < 10 ? "0" : "") + sec;
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.popupPad
        spacing: 6

        // The bar's copy of this is masked to a 22px circle; here there is
        // room to show the cover as the square it actually is.
        //
        // Drawn at the panel width, or at the artwork's own resolution when
        // that is smaller -- never upscaled. A Chromium player publishes a
        // 120-150px cover, and stretching that to fill the panel is a soft,
        // obviously-interpolated square; a player with real artwork
        // (Spotify, mpv) still fills the full width. The panel keeps its
        // width either way, so the menu does not resize per track.
        Item {
            id: cover
            visible: root.artUrl.length > 0
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: coverImage.implicitWidth > 0
                ? Math.min(body.width, coverImage.implicitWidth, coverImage.implicitHeight)
                : body.width
            Layout.preferredHeight: Layout.preferredWidth
            Layout.bottomMargin: 2

            Image {
                id: coverImage
                anchors.fill: parent
                source: root.artUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                // No sourceSize: under PreserveAspectCrop it is a decode
                // *target*, not a cap -- Qt scales a 120px cover up to meet
                // it, and implicitWidth then reports the request rather than
                // the artwork, which is the one number the sizing above
                // needs. Left unset, implicitWidth is the true source size.
                // mipmap because a real cover is downscaled several times.
                mipmap: true
                visible: false
            }

            Rectangle {
                id: coverMask
                anchors.fill: parent
                radius: 8
                visible: false
                layer.enabled: true
            }

            MultiEffect {
                anchors.fill: parent
                source: coverImage
                maskEnabled: true
                maskSource: coverMask
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.title
            color: Theme.lavender
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            visible: root.artist.length > 0
            text: root.artist
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            elide: Text.ElideRight
        }

        // Track Position & Seek Progress Bar
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 6
            visible: root.player !== null && root.player.length > 0

            Text {
                text: root.formatTime(root.player ? root.player.position : 0)
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }

            Rectangle {
                id: sliderTrack
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Theme.surface0

                Rectangle {
                    id: sliderProgress
                    height: parent.height
                    radius: 3
                    color: sliderMouse.containsMouse ? Theme.mauve : Theme.blue
                    width: {
                        if (!root.player || !root.player.length || root.player.length <= 0) return 0;
                        const pos = Math.max(0, Math.min(root.player.position, root.player.length));
                        return parent.width * (pos / root.player.length);
                    }
                    Behavior on width {
                        enabled: !sliderMouse.pressed
                        NumberAnimation { duration: 150 }
                    }
                }

                MouseArea {
                    id: sliderMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.player && root.player.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor

                    function doSeek(mouseX) {
                        if (!root.player || !root.player.canSeek || !root.player.length || sliderTrack.width <= 0) return;
                        const pct = Math.max(0, Math.min(1, mouseX / sliderTrack.width));
                        root.player.position = pct * root.player.length;
                    }

                    onClicked: mouse => doSeek(mouse.x)
                    onPositionChanged: mouse => { if (pressed) doSeek(mouse.x); }
                }
            }

            Text {
                text: root.formatTime(root.player ? root.player.length : 0)
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 3
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 4

            Repeater {
                // Glyphs are private-use codepoints: \uXXXX escapes only.
                model: [
                    { glyph: "\uf048", accent: Theme.blue, action: "previous" },
                    { glyph: "",        accent: Theme.green, action: "toggle" },
                    { glyph: "\uf051", accent: Theme.blue, action: "next" }
                ]

                Rectangle {
                    required property var modelData

                    readonly property bool enabled: {
                        if (root.player === null) return false;
                        switch (modelData.action) {
                        case "previous": return root.player.canGoPrevious;
                        case "next":     return root.player.canGoNext;
                        default:         return root.player.canTogglePlaying;
                        }
                    }

                    Layout.fillWidth: true
                    implicitHeight: 30
                    radius: 6
                    color: btnMouse.containsMouse && enabled ? Theme.surface0 : "transparent"

                    Text {
                        anchors.centerIn: parent
                        // Play/pause shows the action it performs.
                        text: modelData.action === "toggle"
                            ? (root.playing ? "\uf04c" : "\uf04b")
                            : modelData.glyph
                        color: !parent.enabled ? Theme.overlay0
                             : btnMouse.containsMouse ? modelData.accent : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 2
                    }

                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (!parent.enabled) return;
                            switch (modelData.action) {
                            case "previous": root.previousTrack(); break;
                            case "next":     root.nextTrack(); break;
                            default:         root.togglePlay(); break;
                            }
                        }
                    }
                }
            }
        }
    }
}
