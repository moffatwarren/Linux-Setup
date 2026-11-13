import Quickshell
import Quickshell.Hyprland
import QtQuick

// Workspaces and media on the left; clock and weather in the middle, with the
// clock at the exact centre; status modules on the right.
PanelWindow {
    id: bar

    required property var modelData
    screen: modelData

    readonly property string monitorName: {
        const m = Hyprland.monitorFor(bar.screen);
        return m ? String(m.name) : "";
    }

    anchors {
        top: true
        left: true
        right: true
    }
    // left/right match hyprland's gaps_out (look.lua) so the bar's ends line up
    // with the outer edge of a tiled window's border.
    margins {
        top: 2
        left: 5
        right: 5
    }
    implicitHeight: 30
    // The window stays transparent so the slab below can have rounded ends;
    // the wallpaper shows through the margins and around the corners.
    color: "transparent"

    // One floating capsule in the modules' own colour, so the pills dissolve
    // into it and the bar reads as a single solid slab. Declared first, so it
    // sits behind the module Rows.
    Rectangle {
        anchors.fill: parent
        color: Theme.pill
        radius: Theme.barRadius
    }

    Row {
        id: leftModules
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        // Wider than the other rows' 2: the album art is a circle like the
        // workspace dots, and at 2 it reads as one more workspace.
        spacing: 10

        WorkspacesPill {
            monitorName: bar.monitorName
        }

        // Capped at the gap up to the clock: a track title is unbounded and
        // would otherwise run over the middle of the bar.
        MediaGroup {
            id: media
            maxWidth: clock.x - (leftModules.x + media.x) - 8
        }
    }

    // The clock is the exact centre of the bar, and the weather hangs off its
    // right edge. Anchored rather than sharing one centred Row, because a Row
    // would centre the *group*, and the clock would sit off-centre by half the
    // weather's width -- which changes with the temperature.
    ClockPill {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }

    WeatherPill {
        anchors.left: clock.right
        anchors.leftMargin: 2
        anchors.verticalCenter: parent.verticalCenter
    }

    Row {
        id: rightModules
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        RecorderPill {}

        AudioPill {}

        BluetoothPill {}

        TailscalePill {}

        PiaPill {}

        NetworkPill {}

        NotificationPill {
            monitorName: bar.monitorName
        }

        PowerProfilePill {}

        BatteryPill {}

        UpdatePill {}

        PowerPill {}
    }
}
