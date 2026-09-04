import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects

// waybar: "image#album-art" + "custom/media-title", both driven by media.sh on
// a 2 second poll. MPRIS is event-driven, so the polling (and the script) go away.
//
// Click either the art or the title to open MediaMenu -- previous, play/pause,
// next -- rather than binding playback to a click and a skip to a double-click,
// which made every skip toggle playback on its way through.
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

    function toggleMenu() {
        if (mediaMenu.open) mediaMenu.requestClose();
        else mediaMenu.open = true;
    }

    // Anchored to the whole module, so the menu is centred under art + title
    // however wide the track name happens to be.
    MediaMenu {
        id: mediaMenu
        anchorItem: root
        player: root.player
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
            onClicked: root.toggleMenu()
        }
    }

    Pill {
        anchors.verticalCenter: parent.verticalCenter
        label: root.artist.length > 0 ? root.artist + " - " + root.title : root.title
        // The menu is anchored to the whole Row (art + title), but the title is
        // most of the module's width, so this is what hands off on hover.
        menu: mediaMenu
        onClicked: root.toggleMenu()
    }
}
