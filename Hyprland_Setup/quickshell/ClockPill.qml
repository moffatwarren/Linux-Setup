import Quickshell
import QtQuick

// waybar: "clock" -- format "{:%I:%M %p  %d-%b-%Y}", double-click opens calendar.
Pill {
    id: root

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // Midnight of the current day. A `date` property only emits a change when
    // the value actually differs, so the calendar's grid is rebuilt once a day
    // rather than once a second.
    readonly property date today: new Date(clock.date.getFullYear(),
                                           clock.date.getMonth(),
                                           clock.date.getDate())

    label: Qt.formatDateTime(clock.date, "hh:mm AP  dd-MMM-yyyy")
    labelColor: Theme.blue

    onDoubleClicked: Quickshell.execDetached(["brave-origin", "--app=https://calendar.google.com"])

    CalendarPopup {
        anchorItem: root
        requested: root.hovered
        date: root.today
    }
}
