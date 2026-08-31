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
    margins {
        top: 2
        left: 2
        right: 2
    }
    implicitHeight: 30
    color: "transparent"

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        ClockPill {}

        // weather.sh --update, 10 minute refresh (waybar interval: 600)
        ScriptPill {
            command: "~/.config/hypr/scripts/weather.sh --update"
            intervalMs: 600000
            rightClickCommand: "~/.config/hypr/scripts/weather.sh --openWeather"
        }

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

        AudioPill {}

        BluetoothPill {}

        TailscalePill {}

        // pia.sh --status
        ScriptPill {
            command: "~/.config/hypr/scripts/pia.sh --status"
            // waybar coloured #custom-pia by class; red for disconnected as requested.
            altColors: ({
                "connected":     Theme.green,
                "connecting":    Theme.yellow,
                "disconnecting": Theme.yellow,
                "disconnected":  Theme.red,
                "error":         Theme.red
            })
            prefix: "\udb80\udda7 PIA: "
            doubleClickCommand: "~/.config/hypr/scripts/pia.sh --toggle"
        }

        NetworkPill {}

        PowerProfilePill {}

        BatteryPill {}
    }
}
