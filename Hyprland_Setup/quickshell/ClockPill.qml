import Quickshell
import QtQuick

// waybar: "clock" -- format "{:%I:%M %p  %d-%b-%Y}". Left-click opens the
// month grid; Google Calendar is a link in its footer.
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

    // Left-click opens the calendar, the way every other pill that owns a
    // drop-down does. Google Calendar moved into that panel's footer: `clicked`
    // arrives before `doubleClicked`, so keeping it on the double-click would
    // have opened the panel on the way to the browser.
    menu: calendar
    onClicked: root.menuOpen ? calendar.requestClose() : root.openMenu()

    CalendarPopup {
        id: calendar
        anchorItem: root
        date: root.today
        onCalendarRequested: Quickshell.execDetached(
            ["brave-origin", "--app=https://calendar.google.com"])
    }
}
