import Quickshell
import QtQuick

// The time, at the exact centre of the bar, with the date to its right. The weather moved into its drop-down (ClockMenu),
// which is the header, the month and the week's forecast in one.
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
    labelColor: Theme.blue

    // The date hangs off the time's right edge, and the pill hugs the two of
    // them, so the time sits left of the pill's centre by `timeShift`. Bar.qml
    // moves the pill right by the same amount, which puts the time, not the
    // pill, on the bar's centre line. A pill padded out symmetrically would do
    // the same without the offset, but its open-menu highlight would then
    // carry a blank date-sized stretch on the left.
    readonly property real dateGap: 12
    readonly property real timeShift: (dateGap + monthDay.implicitWidth) / 2
    contentWidth: time.implicitWidth + dateGap + monthDay.implicitWidth

    Text {
        id: time
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.contentOffset - root.timeShift
        text: Qt.formatDateTime(clock.date, "hh:mm AP")
        color: root.labelColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 2
        font.bold: true
    }

    // On the time's baseline, not centred beside it: two sizes centred on each
    // other leave the smaller text floating above the line. A step dimmer than
    // the time, so the time is still what the eye lands on. Reads `today`,
    // which changes at midnight, not `clock.date`, which ticks every second.
    Text {
        id: monthDay
        anchors.left: time.right
        anchors.leftMargin: root.dateGap
        anchors.baseline: time.baseline
        text: Qt.formatDate(root.today, "MMM d")
        color: Qt.darker(root.labelColor, 1.2)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
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
