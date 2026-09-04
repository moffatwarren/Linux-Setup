import Quickshell
import Quickshell.Hyprland
import QtQuick

// Layout mirrors the waybar config's modules-left / -center / -right.
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
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        ClockPill {}

        WeatherPill {}

        MediaGroup {}
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        WorkspacesPill {
            monitorName: bar.monitorName
        }
    }

    Row {
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
