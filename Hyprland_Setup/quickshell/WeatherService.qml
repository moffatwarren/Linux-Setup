pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The weather, for the clock menu. hypr/scripts/weather-forecast.sh is the
// whole backend; this polls it, parses it and holds the answer.
//
// It used to live inside WeatherPill, which was a bar module of its own. The
// weather moved into the clock's drop-down and the pill went, so the poll needed
// a home that is not a module -- and a singleton is the better one anyway, for
// the reason UpdateService is one: there is one Bar per monitor, and a poll per
// Bar ran the script once per screen.
Singleton {
    id: root

    readonly property string scriptPath:
        Quickshell.env("HOME") + "/.config/hypr/scripts/weather-forecast.sh"

    // "North Surrey, British Columbia" -- wttr.in's area and region.
    property string place: ""
    // The area alone, for the clock menu's header, where the region does not fit.
    readonly property string city: place.split(",")[0].trim()
    // [{ date: "2026-08-31", code, max, min, pop, sunrise, sunset }, …] straight
    // from the script. sunrise/sunset are Unix seconds. Every field but `date`
    // may be absent.
    property var days: []
    // [{ t, code, temp, day }, …] one per hour from the current one, t in Unix
    // seconds and day Open-Meteo's is_day. Drawn by HourlyChart.
    property var hours: []
    // { code, temp, day } -- any field may be absent if Open-Meteo omitted it.
    property var current: ({})
    property string unit: ""
    // When the data was fetched, in Unix seconds -- the cache file's mtime, not
    // the time of this poll, so a tick served from cache (most of them) still
    // reports the age of the reading it is showing.
    property double updatedAt: 0
    // Only set by the Refresh button, never by the background poll.
    property bool refreshing: false

    readonly property bool hasTemp: current.temp !== undefined
    readonly property var condition: WeatherCodes.condition(current.code, current.day)

    // The temperature is coloured by how warm it is, so the colour says
    // something. Thresholds are in °C; a °F reading is converted first.
    function tempColor(t) {
        if (t === undefined) return Theme.text;
        const c = root.unit === "F" ? (t - 32) * 5 / 9 : t;
        if (c <= 0) return Theme.sky;
        if (c <= 10) return Theme.teal;
        if (c <= 20) return Theme.green;
        if (c <= 27) return Theme.yellow;
        if (c <= 32) return Theme.peach;
        return Theme.red;
    }

    // A normal poll. Usually a `cat` of the ten-minute cache, so it is cheap
    // enough to run every time the clock menu opens.
    function poll() {
        if (proc.running) return;
        proc.force = false;
        proc.running = true;
    }

    // The Refresh button: ignore the cache's age. A press while a poll is
    // already running is ignored.
    function refresh() {
        if (proc.running) return;
        proc.force = true;
        root.refreshing = true;
        proc.running = true;
    }

    Process {
        id: proc
        // Bound into the command, so it must not be rewritten under a running
        // process -- both callers above guard on `running` first.
        property bool force: false
        command: ["bash", "-lc", root.scriptPath + (force ? " --force" : "")]
        onExited: root.refreshing = false
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
                    root.hours = j.hours !== undefined ? j.hours : [];
                    root.updatedAt = j.updated !== undefined ? Number(j.updated) : 0;
                } catch (e) {
                    console.warn("WeatherService: unparseable weather: " + e);
                }
            }
        }
    }

    // The script caches for the same ten minutes, so a tick that lands on a
    // warm cache is a `cat` rather than a request.
    Timer {
        interval: 600000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }
}
