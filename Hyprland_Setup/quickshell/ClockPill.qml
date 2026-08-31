import Quickshell
import QtQuick

// waybar: "clock" -- format "{:%I:%M %p  %d-%b-%Y}", double-click opens calendar.
Pill {
    id: root

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    label: Qt.formatDateTime(clock.date, "hh:mm AP  dd-MMM-yyyy")
    labelColor: Theme.blue

    onDoubleClicked: Quickshell.execDetached(["brave-origin", "--app=https://calendar.google.com"])
}
