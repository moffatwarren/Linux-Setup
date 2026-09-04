import Quickshell
import Quickshell.Io
import QtQuick

// waybar: "custom/weather" -- current condition icon and temperature.
// Left-click opens the forecast, which carries the Refresh button.
//
// Not a ScriptPill: weather-forecast.sh already returns the current conditions
// alongside the week ahead, so one poll feeds both the label and the forecast
// panel, and both draw their glyph from the same WMO code table
// (WeatherCodes.qml) instead of the pill showing wttr.in's emoji next to a
// panel full of nerd font icons.
Pill {
    id: root

    property string place: ""
    property var days: []
    // { code, temp } -- either field may be absent if Open-Meteo omitted it.
    property var current: ({})
    property string unit: ""
    // When the data was fetched, in Unix seconds -- the cache file's mtime, not
    // the time of this poll, so a tick served from cache (most of them) still
    // reports the age of the reading it is showing.
    property double updatedAt: 0
    property bool refreshing: false

    readonly property var condition: WeatherCodes.condition(current.code)

    // Only the glyph is coloured by the condition; the temperature stays the
    // bar's normal text colour, the way ScriptPill colours just the state word.
    richText: true
    label: {
        if (current.temp === undefined) return "";
        return '<font color="' + condition.color + '">' + condition.icon + "</font> "
             + Math.round(current.temp) + "°" + unit;
    }

    // Left-click opens the forecast, the way every other pill that owns a
    // drop-down does. The right button is unbound: forcing a re-fetch was its
    // one job and it is a button in the forecast's footer now, the way the
    // clock's double-click became a link in CalendarPopup's.
    menu: forecast
    onClicked: root.menuOpen ? forecast.requestClose() : root.openMenu()

    function refresh() {
        // The command is bound to `force`, so it must not be rewritten under a
        // running process; a second click mid-fetch is simply ignored.
        if (weather.running) return;
        weather.force = true;
        root.refreshing = true;
        weather.running = true;
    }

    Process {
        id: weather
        // --force makes the script ignore the cache's age. Cleared again in
        // onExited so the scheduled polls stay cheap.
        property bool force: false
        command: ["bash", "-lc", "~/.config/hypr/scripts/weather-forecast.sh"
                                 + (force ? " --force" : "")]
        onExited: {
            weather.force = false;
            root.refreshing = false;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = text.trim();
                // The script prints nothing rather than guessing when it cannot
                // reach either service -- keep the last good reading.
                if (raw.length === 0) return;
                try {
                    const j = JSON.parse(raw);
                    root.place = j.place !== undefined ? String(j.place) : "";
                    root.unit = j.unit !== undefined ? String(j.unit) : "";
                    root.current = j.current !== undefined ? j.current : ({});
                    root.days = j.days !== undefined ? j.days : [];
                    root.updatedAt = j.updated !== undefined ? Number(j.updated) : 0;
                } catch (e) {
                    console.warn("WeatherPill: unparseable weather: " + e);
                }
            }
        }
    }

    // waybar interval: 600. The script caches for the same ten minutes, so a
    // tick that lands on a warm cache is a `cat` rather than a request.
    Timer {
        interval: 600000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!weather.running) weather.running = true
    }

    ForecastPopup {
        id: forecast
        anchorItem: root
        place: root.place
        days: root.days
        updatedAt: root.updatedAt
        refreshing: root.refreshing
        emptyText: "Fetching forecast…"
        onRefreshRequested: root.refresh()
    }
}
