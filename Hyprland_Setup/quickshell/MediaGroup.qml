import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects

// waybar: "image#album-art" + "custom/media-title", both driven by media.sh on
// a 2 second poll. MPRIS is event-driven, so the polling (and the script) go away.
//
// Click either the art or the title to play/pause, double-click either to skip.
Row {
    id: root

    spacing: 2

    readonly property var players: Mpris.players.values
    readonly property var player: {
        if (players.length === 0) return null;
        const playing = players.filter(p => p.isPlaying);
        return playing.length > 0 ? playing[0] : players[0];
    }
    readonly property string title: player && player.trackTitle ? String(player.trackTitle) : ""
    readonly property string artist: player && player.trackArtist ? String(player.trackArtist) : ""
    readonly property string artUrl: player && player.trackArtUrl ? String(player.trackArtUrl) : ""

    visible: title.length > 0

    // QML delivers `clicked` before `doubleClicked`, so acting on a click
    // immediately would toggle playback on the way to skipping a track. Hold
    // the single-click action until the double-click window has passed.
    Timer {
        id: pendingClick
        interval: 250
        onTriggered: root.togglePlay()
    }

    function togglePlay() {
        if (player && player.canTogglePlaying) player.togglePlaying();
    }

    function nextTrack() {
        if (player && player.canGoNext) player.next();
    }

    function handleClick() {
        pendingClick.restart();
    }

    function handleDoubleClick() {
        pendingClick.stop();
        nextTrack();
    }

    Item {
        width: artUrl.length > 0 ? Theme.pillHeight : 0
        height: Theme.pillHeight
        visible: artUrl.length > 0
        anchors.verticalCenter: parent.verticalCenter

        Image {
            id: art
            anchors.fill: parent
            source: root.artUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: false
        }

        // style.css gave #album-art border-radius 50%; mask the image to match.
        Rectangle {
            id: mask
            anchors.fill: parent
            radius: width / 2
            visible: false
            layer.enabled: true
        }

        MultiEffect {
            anchors.fill: parent
            source: art
            maskEnabled: true
            maskSource: mask
        }

        // Declared after MultiEffect so it sits on top and receives the clicks.
        MouseArea {
            anchors.fill: parent
            onClicked: root.handleClick()
            onDoubleClicked: root.handleDoubleClick()
        }
    }

    Pill {
        anchors.verticalCenter: parent.verticalCenter
        label: root.artist.length > 0 ? root.artist + " - " + root.title : root.title
        onClicked: root.handleClick()
        onDoubleClicked: root.handleDoubleClick()
    }
}
