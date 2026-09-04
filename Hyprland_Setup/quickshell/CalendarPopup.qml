import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

// Drop-down for the clock: the current month laid out as a grid, with today
// picked out. Built like ListPopup (same anchoring, same Catppuccin frame)
// rather than reusing it, because a month is a grid and ListPopup only knows
// how to stack rows.
//
// It is opened by a click, not by hover, so it dismisses the way every other
// drop-down on this bar does -- Escape, or a click anywhere outside via
// HyprlandFocusGrab. A hover panel cannot own the keyboard, so it could not
// answer Escape; a panel you open deliberately should close deliberately too.
MenuPopup {
    id: root

    // The clock's date, so the grid follows midnight without a timer of its own.
    property date date: new Date()

    signal calendarRequested()

    readonly property int cellSize: 28
    readonly property int columns: 7

    // Sunday-first unless the locale says otherwise.
    readonly property int firstDayOfWeek: Qt.locale().firstDayOfWeek

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
        const d = root.date;
        const year = d.getFullYear();
        const month = d.getMonth();
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
                isToday: cell.getDate() === d.getDate() && cell.getMonth() === month,
                isWeekend: dow === 0 || dow === 6
            });
        }
        return out;
    }

    implicitWidth: body.implicitWidth + 28
    implicitHeight: body.implicitHeight + 24

    ColumnLayout {
        id: body
        anchors.centerIn: parent
        spacing: 6

        // Month and year, with the full date underneath -- the pill itself
        // only has room for the numeric form.
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDate(root.date, "MMMM yyyy")
            color: Theme.lavender
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDate(root.date, "dddd, d MMMM")
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            implicitHeight: 1
            color: Theme.surface1
        }

        GridLayout {
            columns: root.columns
            columnSpacing: 0
            rowSpacing: 2

            Repeater {
                model: root.weekdays

                Text {
                    required property string modelData
                    Layout.preferredWidth: root.cellSize
                    Layout.preferredHeight: root.cellSize - 6
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
                    Layout.preferredWidth: root.cellSize
                    Layout.preferredHeight: root.cellSize

                    // Today's marker: a filled disc, so the number reads as
                    // selected rather than merely recoloured.
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

        // Google Calendar used to be the pill's double-click. The left
        // button opens this panel now, and `clicked` arrives before
        // `doubleClicked`, so a double-click would have opened the panel on
        // its way to the browser. It moves into the footer instead, the way
        // pavucontrol and blueman sit at the foot of their own menus.
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 2
            implicitHeight: 1
            color: Theme.surface1
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
                onClicked: {
                    root.requestClose();
                    root.calendarRequested();
                }
            }
        }
    }
}
