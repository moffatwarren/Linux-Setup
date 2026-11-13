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

    // Drawn rather than labelled, the way TailscalePill draws its logo: the
    // time is a size up from the date, and a Pill label is one font at one
    // size. Both are bold, so the clock stands out from the rest of the bar.
    label: ""
    hasContent: true
    contentWidth: face.width
    labelColor: Theme.blue

    Item {
        id: face
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.contentOffset
        width: time.implicitWidth + date.anchors.leftMargin + date.implicitWidth
        height: time.implicitHeight

        Text {
            id: time
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "hh:mm AP")
            color: root.labelColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
        }

        // On the time's baseline, not centred beside it: two sizes centred
        // on each other leave the smaller text floating above the line.
        Text {
            id: date
            anchors.left: time.right
            anchors.leftMargin: 12
            anchors.baseline: time.baseline
            text: Qt.formatDateTime(clock.date, "dd-MMM-yyyy")
            // A step dimmer than the time, so the time is what the eye lands on.
            color: Qt.darker(root.labelColor, 1.2)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
    }

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
            ["bash", Quickshell.env("HOME") + "/.config/hypr/scripts/launch-browser.sh", "--app=https://calendar.google.com"])
    }
}
