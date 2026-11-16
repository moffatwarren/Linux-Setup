import Quickshell
import QtQuick

// The time, at the exact centre of the bar, and nothing else: the date and the
// weather used to sit beside it and moved into its drop-down (ClockMenu), which
// is the header, the month and the week's forecast in one.
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

    // Drawn rather than labelled: a Pill label is one regular font, and the
    // clock is a size up and bold, so it stands out from the rest of the bar.
    label: ""
    hasContent: true
    contentWidth: time.implicitWidth
    labelColor: Theme.blue

    Text {
        id: time
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.contentOffset
        text: Qt.formatDateTime(clock.date, "hh:mm AP")
        color: root.labelColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 2
        font.bold: true
    }

    menu: clockMenu
    onClicked: root.menuOpen ? clockMenu.requestClose() : root.openMenu()

    ClockMenu {
        id: clockMenu
        anchorItem: root
        now: clock.date
        today: root.today
        onCalendarRequested: Quickshell.execDetached(
            ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/launch-browser.sh", "--app=https://calendar.google.com"])
    }
}
