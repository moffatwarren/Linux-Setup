import Quickshell
import QtQuick
import QtQuick.Layouts

// Hover panel for the weather module: the next seven days as a table.
// Built like CalendarPopup (same frame, anchoring and open delay) rather than
// reusing ListPopup, because a forecast day is six aligned columns and
// ListPopup only knows how to put one label opposite one detail.
PopupWindow {
    id: root

    property Item anchorItem: null
    property bool requested: false
    property string place: ""
    // [{ date: "2026-08-31", code: 3, max: 22.5, min: 11, pop: 2 }, …] straight
    // from weather-forecast.sh; every field but `date` may be absent.
    property var days: []
    property string emptyText: ""
    property int delayMs: 300

    readonly property bool hasContent: days.length > 0 || emptyText.length > 0

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

    // The WMO code table lives in WeatherCodes so the pill can use the same
    // glyphs -- see WeatherCodes.qml.
    function condition(code) { return WeatherCodes.condition(code); }

    function temp(v) { return v === undefined ? "" : Math.round(v) + "°"; }

    function popColor(pop) {
        return pop >= 60 ? Theme.blue : pop >= 20 ? Theme.subtext0 : Theme.overlay0;
    }

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 6

    implicitWidth: body.implicitWidth + 28
    implicitHeight: body.implicitHeight + 24
    color: "transparent"

    // Bound rather than set from onRequestedChanged: a handler never fires for
    // a property that is already true at construction.
    property bool delayPassed: false
    visible: requested && hasContent && delayPassed

    onRequestedChanged: {
        if (requested) openTimer.restart();
        else { openTimer.stop(); delayPassed = false; }
    }
    Component.onCompleted: if (requested) openTimer.restart()

    Timer {
        id: openTimer
        interval: root.delayMs
        onTriggered: root.delayPassed = true
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

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Theme.base
        border.width: 1
        border.color: Theme.surface1

        ColumnLayout {
            id: body
            anchors.centerIn: parent
            spacing: 5

            Text {
                text: "7-day forecast"
                color: Theme.lavender
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                text: root.place
                visible: root.place.length > 0
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

            Text {
                text: root.emptyText
                visible: root.days.length === 0 && root.emptyText.length > 0
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

                    readonly property var cond: root.condition(modelData.code)
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
        }
    }
}
