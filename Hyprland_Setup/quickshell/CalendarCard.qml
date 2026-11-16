import QtQuick
import QtQuick.Layouts

// The middle card of the clock menu: the year's progress, then the month as a
// grid, today picked out, with the leading and trailing days of the
// neighbouring months dimmed so every week is complete.
//
// This was CalendarPopup, a drop-down of its own; it became a card when the
// date and the weather moved off the bar and into the clock's one menu. The
// "Monday, 16 November" line under the month went with the move -- the menu's
// header already says it.
MenuCard {
    id: root

    // The clock's midnight-truncated date, so the grid follows midnight without
    // a timer of its own.
    property date date: new Date()
    property date displayDate: date
    // True while the menu is up. Showing the card returns to this month and
    // re-reads the year's progress.
    property bool shown: false

    onShownChanged: if (shown) displayDate = date
    onDateChanged: displayDate = date

    signal calendarRequested()

    readonly property int currentYear: root.date.getFullYear()
    readonly property real yearProgress: {
        const _ = root.shown;
        const now = new Date();
        const y = root.currentYear;
        const start = new Date(y, 0, 1);
        const end = new Date(y + 1, 0, 1);
        const refTime = (y === now.getFullYear()) ? now.getTime() : root.date.getTime();
        return Math.max(0, Math.min(1, (refTime - start.getTime()) / (end.getTime() - start.getTime())));
    }
    readonly property int yearPercent: Math.round(root.yearProgress * 100)

    // The narrowest a day cell may be, which is what the card asks for. The
    // forecast card below is wider, so in practice the cells stretch to share
    // its width -- see `cellWidth`.
    readonly property int cellSize: 28
    readonly property int columns: 7
    // Read off the grid's holder, whose implicitWidth is the constant
    // 7 * cellSize -- so the width the cells are given can never feed back into
    // the width the card asks for.
    readonly property int cellWidth: Math.max(root.cellSize, Math.floor(gridHolder.width / root.columns))

    // Sunday-first unless the locale says otherwise.
    readonly property int firstDayOfWeek: Qt.locale().firstDayOfWeek

    function changeMonth(delta) {
        const y = displayDate.getFullYear();
        const m = displayDate.getMonth() + delta;
        displayDate = new Date(y, m, 1);
    }

    readonly property var weekdays: {
        const out = [];
        for (let i = 0; i < 7; i++) {
            const dow = (root.firstDayOfWeek + i) % 7;
            // dayName() takes 7 for Sunday, 1-6 for Monday-Saturday.
            out.push(Qt.locale().dayName(dow === 0 ? 7 : dow, Locale.ShortFormat).substring(0, 2));
        }
        return out;
    }

    // 7 * weeks cells covering the month, padded out with the neighbouring
    // months' days so every week is complete. Trailing weeks that fall entirely
    // outside the month are dropped, so a short month does not leave a blank row.
    readonly property var days: {
        const d = root.displayDate;
        const year = d.getFullYear();
        const month = d.getMonth();
        const today = root.date;
        const lead = (new Date(year, month, 1).getDay() - root.firstDayOfWeek + 7) % 7;
        // Day 0 of the next month is the last day of this one.
        const length = new Date(year, month + 1, 0).getDate();
        const weeks = Math.ceil((lead + length) / 7);

        const out = [];
        for (let i = 0; i < weeks * 7; i++) {
            const cell = new Date(year, month, i - lead + 1);
            const dow = cell.getDay();
            out.push({
                day: cell.getDate(),
                inMonth: cell.getMonth() === month,
                isToday: cell.getDate() === today.getDate() && cell.getMonth() === today.getMonth() && cell.getFullYear() === today.getFullYear(),
                isWeekend: dow === 0 || dow === 6
            });
        }
        return out;
    }

    // Year progress bar
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Text {
            text: root.currentYear + " is " + root.yearPercent + "% complete."
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        Rectangle {
            id: progressTrack
            Layout.fillWidth: true
            implicitHeight: 8
            radius: 4
            color: Theme.surface0
            clip: true

            Rectangle {
                width: progressTrack.width * root.yearProgress
                height: parent.height
                radius: parent.radius
                color: Theme.yellow

                Behavior on width { NumberAnimation { duration: 150 } }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 2
        implicitHeight: 1
        color: Theme.surface0
    }

    // Month and year navigation header
    RowLayout {
        Layout.fillWidth: true
        spacing: 4

        Rectangle {
            implicitWidth: 24; implicitHeight: 24; radius: 6
            color: prevMouse.containsMouse ? Theme.surface0 : "transparent"
            Text {
                anchors.centerIn: parent
                text: "\uf060"
                color: Theme.lavender
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
            MouseArea {
                id: prevMouse; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.changeMonth(-1)
            }
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDate(root.displayDate, "MMMM yyyy")
            color: Theme.lavender
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
        }

        Rectangle {
            visible: root.displayDate.getMonth() !== root.date.getMonth() || root.displayDate.getFullYear() !== root.date.getFullYear()
            implicitWidth: 24; implicitHeight: 24; radius: 6
            color: todayMouse.containsMouse ? Theme.surface0 : "transparent"
            Text {
                anchors.centerIn: parent
                text: "\uf13d"
                color: Theme.blue
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
            MouseArea {
                id: todayMouse; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.displayDate = root.date
            }
        }

        Rectangle {
            implicitWidth: 24; implicitHeight: 24; radius: 6
            color: nextMouse.containsMouse ? Theme.surface0 : "transparent"
            Text {
                anchors.centerIn: parent
                text: "\uf061"
                color: Theme.lavender
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
            MouseArea {
                id: nextMouse; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.changeMonth(1)
            }
        }
    }

    // A positioner rather than a GridLayout, inside a holder with a fixed
    // implicitWidth: a GridLayout's implicit width is the sum of its cells, and
    // the cells take their width from the space they are given, which would be
    // a binding loop.
    Item {
        id: gridHolder
        Layout.fillWidth: true
        implicitWidth: root.columns * root.cellSize
        implicitHeight: grid.height

        Grid {
            id: grid
            anchors.horizontalCenter: parent.horizontalCenter
            columns: root.columns
            rowSpacing: 2

            Repeater {
                model: root.weekdays

                Text {
                    required property string modelData
                    width: root.cellWidth
                    height: root.cellSize - 6
                    text: modelData
                    color: Theme.overlay0
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                }
            }

            Repeater {
                model: root.days

                Item {
                    required property var modelData
                    width: root.cellWidth
                    height: root.cellSize

                    // Today's marker: a filled disc, so the number reads as
                    // selected rather than merely recoloured. Sized off the
                    // height, so it stays a circle when the cells stretch.
                    Rectangle {
                        anchors.centerIn: parent
                        width: root.cellSize - 4
                        height: width
                        radius: width / 2
                        visible: modelData.isToday
                        color: Theme.blue
                    }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.day
                        color: modelData.isToday ? Theme.base
                             : !modelData.inMonth ? Theme.surface2
                             : modelData.isWeekend ? Theme.subtext0
                             : Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: modelData.isToday
                    }
                }
            }
        }
    }

    // Google Calendar was the clock pill's double-click once; it sits at the
    // foot of the calendar the way pavucontrol and blueman sit at the foot of
    // their own menus.
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 2
        implicitHeight: 1
        color: Theme.surface0
    }

    Text {
        Layout.fillWidth: true
        text: "Open Google Calendar\u2026"
        color: calMouse.containsMouse ? Theme.blue : Theme.overlay0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1

        MouseArea {
            id: calMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.calendarRequested()
        }
    }
}
