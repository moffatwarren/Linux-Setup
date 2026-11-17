import QtQuick
import QtQuick.Layouts

// The clock's drop-down, and the only place the date and the weather appear:
// they used to be on the bar beside the time, with a menu each, and both
// moved in here so the bar carries the time alone.
//
// Three cards, top to bottom:
//
//  - the header: where you are and the date on the left, the time with its
//    time zone on the right, and under them a track of the whole day with
//    daylight marked and a dot for now;
//  - CalendarCard, the month;
//  - ForecastCard, the weather now and the week ahead.
//
// The current weather was a small temperature and glyph in the header, beside
// the time, and was too easy to miss there at body size next to a 24px clock.
// It is the top of ForecastCard now, at a size of its own.
//
// The weather is WeatherService's; nothing here runs a process.
MenuPopup {
    id: root

    // The bar clock's tick, and its midnight-truncated date. Fed by ClockPill
    // rather than read from a SystemClock of this menu's own, so the bar and
    // the menu can never show two different minutes.
    property date now: new Date()
    property date today: new Date()

    signal calendarRequested()

    // Opening is a poll: usually a `cat` of the ten-minute cache, but after a
    // suspend the background timer can be most of an interval behind, and the
    // menu should not open on hours-old weather.
    onOpenChanged: if (open) WeatherService.poll()

    // Today's row of the forecast, for its sunrise and sunset. Matched by date
    // rather than taken as days[0], so a cache that outlived midnight (no
    // network) is not read as today; it falls back to days[0] all the same,
    // because yesterday's sunrise is a minute off, not wrong.
    readonly property var todayWeather: {
        const iso = Qt.formatDate(root.today, "yyyy-MM-dd");
        const ds = WeatherService.days;
        for (let i = 0; i < ds.length; i++)
            if (ds[i].date === iso) return ds[i];
        return ds.length > 0 ? ds[0] : ({});
    }

    implicitWidth: body.implicitWidth + 2 * Theme.popupPad
    implicitHeight: body.implicitHeight + 2 * Theme.popupPad

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: Theme.popupPad
        spacing: 8

        MenuCard {
            Layout.fillWidth: true
            spacing: 10

            // Two rows, each on a shared baseline: place / time on the first,
            // date / time zone on the second. Anchored rather than
            // laid out, because baselines are what line the three sizes up.
            Item {
                id: face
                Layout.fillWidth: true
                // The place elides, so it asks for no more than a short name.
                implicitWidth: 96 + 14 + time.implicitWidth + 3 + ampm.implicitWidth
                implicitHeight: time.implicitHeight + zone.implicitHeight - 4

                Text {
                    id: place
                    anchors.left: parent.left
                    anchors.right: time.left
                    anchors.rightMargin: 14
                    anchors.baseline: time.baseline
                    // Before the first reading there is no place; the weekday
                    // is the next most useful word to put there.
                    text: WeatherService.city.length > 0 ? WeatherService.city
                                                         : Qt.formatDate(root.today, "dddd")
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }

                Text {
                    id: date
                    anchors.left: parent.left
                    anchors.baseline: zone.baseline
                    text: Qt.formatDate(root.today, "ddd MMM d")
                    color: Theme.subtext0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }

                Text {
                    id: time
                    anchors.right: ampm.left
                    anchors.rightMargin: 3
                    anchors.top: parent.top
                    // The hour is worked out here, not formatted: Qt's "h" is
                    // 12-hour only when the SAME format string has an "AP" in
                    // it, and the AM/PM is a separate, smaller Text -- so
                    // "h:mm" alone read "13:39" beside a "PM".
                    text: (root.now.getHours() % 12 || 12) + Qt.formatDateTime(root.now, ":mm")
                    color: Theme.blue
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 12
                    font.bold: true
                }

                Text {
                    id: ampm
                    anchors.right: parent.right
                    anchors.baseline: time.baseline
                    text: Qt.formatDateTime(root.now, "AP")
                    color: Qt.darker(Theme.blue, 1.2)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: true
                }

                // "t" is the zone's abbreviation, from the system's tzdata
                // (MST). Not "tttt": Qt's long names come from its own locale
                // data, which still calls America/Vancouver "Pacific Standard
                // Time" although BC has been on permanent UTC-7 since
                // 1 Nov 2026 (measured with `qs -p`).
                Text {
                    id: zone
                    anchors.right: parent.right
                    anchors.top: time.bottom
                    anchors.topMargin: -4
                    text: Qt.formatDateTime(root.now, "t")
                    color: Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            SunTrack {
                Layout.fillWidth: true
                now: root.now
                sunrise: root.todayWeather.sunrise !== undefined ? root.todayWeather.sunrise : 0
                sunset: root.todayWeather.sunset !== undefined ? root.todayWeather.sunset : 0
            }
        }

        CalendarCard {
            Layout.fillWidth: true
            date: root.today
            shown: root.open
            onCalendarRequested: {
                root.requestClose();
                root.calendarRequested();
            }
        }

        ForecastCard {
            Layout.fillWidth: true
            shown: root.open
        }
    }
}
