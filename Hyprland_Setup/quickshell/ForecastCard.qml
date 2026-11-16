import QtQuick
import QtQuick.Layouts

// The bottom card of the clock menu: the weather now, large, then the next
// seven days as a table, then how old the reading is and the button that
// forces a new one.
//
// This was ForecastPopup, the weather pill's drop-down; it became a card when
// the weather moved off the bar and into the clock's menu. The place name it
// used to carry moved into the menu's header. It reads WeatherService
// directly, the way UpdateMenu reads UpdateService.
MenuCard {
    id: root

    // True while the menu is up; drives the "N min ago" re-render.
    property bool shown: false

    readonly property var days: WeatherService.days
    // The table's "Today" row, for the high, low and rain beside the current
    // reading -- the same row, so the two can never disagree.
    readonly property var today: days.length > 0 ? days[0] : ({})

    // Re-read every half minute while the menu is open, so "5 min ago" does
    // not sit there going stale in front of you. Nothing drives it when the
    // menu is closed.
    property double nowMs: Date.now()

    // "2026-08-31" -> a *local* midnight. new Date(string) reads an ISO date as
    // UTC, which lands on the previous day west of Greenwich and would shift
    // every weekday name by one.
    function localDate(iso) {
        const p = String(iso).split("-");
        return new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]));
    }

    function dayLabel(iso, index) {
        if (index === 0) return "Today";
        const dow = root.localDate(iso).getDay();
        // dayName() takes 7 for Sunday, 1-6 for Monday-Saturday.
        return Qt.locale().dayName(dow === 0 ? 7 : dow, Locale.ShortFormat).substring(0, 3);
    }

    function temp(v) { return v === undefined ? "" : Math.round(v) + "°"; }

    // Relative for anything inside a day, absolute past that -- "31 h ago" is
    // arithmetic the reader has to do, a date is not.
    function agoText(sec) {
        const mins = Math.floor((root.nowMs / 1000 - sec) / 60);
        if (mins < 1) return "just now";
        if (mins < 60) return mins + " min ago";
        const hrs = Math.floor(mins / 60);
        if (hrs < 24) return hrs + (hrs === 1 ? " hour ago" : " hours ago");
        return Qt.formatDateTime(new Date(sec * 1000), "d MMM, h:mm ap");
    }

    function popColor(pop) {
        return pop >= 60 ? Theme.blue : pop >= 20 ? Theme.subtext0 : Theme.overlay0;
    }

    spacing: 5

    Timer {
        interval: 30000
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: root.nowMs = Date.now()
    }

    // Column widths are measured off the widest content each column can hold,
    // so the table stays still instead of reflowing as the numbers change
    // width from one refresh to the next. advanceWidth, not width: width is the
    // ink bounding box, which is a fraction narrower than the space the same
    // string is laid out in, and every condition would elide by one pixel.
    TextMetrics {
        id: dayMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        text: "Today"
    }

    TextMetrics {
        id: iconMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 2
        text: "\ue33d"
    }

    TextMetrics {
        id: condMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        text: "Partly cloudy"
    }

    TextMetrics {
        id: tempMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        text: "-99°"
    }

    TextMetrics {
        id: popMetrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        text: "\ue371 100%"
    }

    // Now: the condition's glyph and the temperature, both well above body
    // size, with the condition in words under the temperature and today's
    // high, low and chance of rain on the right. The glyph takes the
    // condition's colour and the temperature its warmth colour, as everywhere
    // else the weather is drawn.
    RowLayout {
        Layout.fillWidth: true
        visible: WeatherService.hasTemp
        spacing: 12

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: WeatherService.condition.icon
            color: WeatherService.condition.color
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 22
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            Text {
                text: WeatherService.hasTemp
                      ? Math.round(WeatherService.current.temp) + "\u00b0" + WeatherService.unit : ""
                color: WeatherService.tempColor(WeatherService.current.temp)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 14
                font.bold: true
            }

            Text {
                text: WeatherService.condition.text
                color: Theme.subtext1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }

        Item { Layout.fillWidth: true }

        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 2

            Text {
                Layout.alignment: Qt.AlignRight
                visible: root.today.max !== undefined && root.today.min !== undefined
                textFormat: Text.StyledText
                text: '<font color="' + Theme.overlay0 + '">H</font> '
                      + '<font color="' + Theme.peach + '">' + root.temp(root.today.max) + '</font>  '
                      + '<font color="' + Theme.overlay0 + '">L</font> '
                      + '<font color="' + Theme.sapphire + '">' + root.temp(root.today.min) + '</font>'
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                Layout.alignment: Qt.AlignRight
                visible: root.today.pop !== undefined
                text: "\ue371 " + root.today.pop + "% rain"
                color: root.today.pop !== undefined ? root.popColor(root.today.pop) : Theme.overlay0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 2
        visible: WeatherService.hasTemp
        implicitHeight: 1
        color: Theme.surface0
    }

    Text {
        text: "7-day forecast"
        color: Theme.lavender
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 2
        implicitHeight: 1
        color: Theme.surface0
    }

    Text {
        text: "Fetching forecast…"
        visible: root.days.length === 0
        color: Theme.subtext0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // Day | icon | condition | high | low | chance of precipitation.
    // High and low are separate fixed-width cells so their digits line
    // up down the column rather than drifting with the number above.
    Repeater {
        model: root.days

        Row {
            id: dayRow
            required property var modelData
            required property int index

            readonly property var cond: WeatherCodes.condition(modelData.code)
            readonly property bool isToday: index === 0

            spacing: 10

            Text {
                width: Math.ceil(dayMetrics.advanceWidth)
                text: root.dayLabel(dayRow.modelData.date, dayRow.index)
                color: dayRow.isToday ? Theme.lavender : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: dayRow.isToday
            }

            Text {
                width: Math.ceil(iconMetrics.advanceWidth)
                horizontalAlignment: Text.AlignHCenter
                text: dayRow.cond.icon
                color: dayRow.cond.color
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
            }

            Text {
                width: Math.ceil(condMetrics.advanceWidth)
                text: dayRow.cond.text
                elide: Text.ElideRight
                color: Theme.subtext1
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                width: Math.ceil(tempMetrics.advanceWidth)
                horizontalAlignment: Text.AlignRight
                text: root.temp(dayRow.modelData.max)
                color: Theme.peach
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                width: Math.ceil(tempMetrics.advanceWidth)
                horizontalAlignment: Text.AlignRight
                text: root.temp(dayRow.modelData.min)
                color: Theme.sapphire
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            // A droplet, so the column labels itself without the table
            // needing a header row.
            Text {
                width: Math.ceil(popMetrics.advanceWidth)
                horizontalAlignment: Text.AlignRight
                text: dayRow.modelData.pop === undefined
                      ? "" : "\ue371 " + dayRow.modelData.pop + "%"
                color: dayRow.modelData.pop === undefined
                       ? Theme.overlay0 : root.popColor(dayRow.modelData.pop)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: 2
        implicitHeight: 1
        color: Theme.surface0
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        Text {
            // The age stays put through a refresh: the button is where the
            // in-progress state is said, so this row does not have to stop
            // saying the one thing it is here to say.
            text: "Updated " + root.agoText(WeatherService.updatedAt)
            visible: WeatherService.updatedAt > 0
            color: Theme.overlay0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
        }

        Item { Layout.fillWidth: true }

        // The same chip BluetoothMenu and WifiMenu use for Scan.
        Rectangle {
            implicitWidth: refreshLabel.implicitWidth + 16
            implicitHeight: 20
            radius: 6
            color: refreshMouse.containsMouse ? Theme.surface1 : Theme.surface0
            border.width: 1
            border.color: Theme.surface2

            Text {
                id: refreshLabel
                anchors.centerIn: parent
                text: WeatherService.refreshing ? "Refreshing…" : "Refresh"
                color: WeatherService.refreshing ? Theme.yellow : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }

            MouseArea {
                id: refreshMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // The menu stays open on a click -- the point of the button
                // is to watch the numbers land.
                onClicked: WeatherService.refresh()
            }
        }
    }
}
