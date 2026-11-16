import QtQuick

// The line under the clock menu's time: the whole day, midnight to midnight,
// with the daylight between sunrise and sunset marked on it in grey, the part
// of it the sun has already crossed in yellow, a dot for now -- a sun while it
// is up, a moon while it is not -- and the two times written under the ends of
// the daylight.
//
// Grey and full yellow rather than one translucent yellow: a pastel yellow at a
// third opacity on the card's near-black is khaki, the mud the aquarium's far
// fish turned when they were dimmed (see CLAUDE.md, "The tank").
//
// Everything is placed by its time of day on the SYSTEM clock: sunrise and
// sunset arrive as Unix seconds (weather-forecast.sh converts them), and the
// dot is the same `now` the menu's time is drawn from, so the three cannot
// disagree about where in the day they are. If the weather's location is in a
// different zone (a VPN exit somewhere else) the daylight can straddle
// midnight on this clock, and it is drawn as two pieces rather than as a
// negative width.
Item {
    id: root

    property date now: new Date()
    // Unix seconds; 0 when the forecast has none (no reading yet, or a polar
    // day or night). The track and the dot still draw without them.
    property double sunrise: 0
    property double sunset: 0

    readonly property bool hasSun: sunrise > 0 && sunset > 0

    function dayFrac(d) {
        return (d.getHours() * 60 + d.getMinutes() + d.getSeconds() / 60) / 1440;
    }

    readonly property real nowFrac: dayFrac(root.now)
    readonly property real riseFrac: hasSun ? dayFrac(new Date(sunrise * 1000)) : 0
    readonly property real setFrac: hasSun ? dayFrac(new Date(sunset * 1000)) : 0
    // Daylight crosses midnight on this clock -- see the comment at the top.
    readonly property bool wraps: setFrac < riseFrac
    readonly property bool daytime: !hasSun ? false
                                  : wraps ? (nowFrac >= riseFrac || nowFrac < setFrac)
                                  : (nowFrac >= riseFrac && nowFrac < setFrac)

    // [from, to] stretches of the track, split in two where one crosses
    // midnight.
    function segments(from, to) {
        return from <= to ? [[from, to]] : [[from, 1], [0, to]];
    }
    readonly property var daylight: hasSun ? segments(riseFrac, setFrac) : []
    readonly property var travelled: daytime ? segments(riseFrac, nowFrac) : []

    readonly property int dotSize: 10
    readonly property int labelGap: 8

    // Each label is centred under its end of the daylight, kept inside the
    // track, and pushed apart if the two would touch -- which a short winter
    // day far enough north does.
    readonly property var labelX: {
        const W = root.width;
        const clamp = (x, w) => Math.max(0, Math.min(W - w, x));
        const l0 = { k: "rise", w: riseLabel.implicitWidth };
        const l1 = { k: "set", w: setLabel.implicitWidth };
        l0.x = clamp(W * root.riseFrac - l0.w / 2, l0.w);
        l1.x = clamp(W * root.setFrac - l1.w / 2, l1.w);
        // Left to right, whichever that is -- sunset is the left one when the
        // daylight wraps.
        const [l, r] = l0.x <= l1.x ? [l0, l1] : [l1, l0];
        if (r.x < l.x + l.w + root.labelGap) {
            // Side by side about the pair's midpoint, then back inside.
            const total = l.w + root.labelGap + r.w;
            const mid = (l.x + l.w / 2 + r.x + r.w / 2) / 2;
            l.x = Math.max(0, Math.min(W - total, mid - total / 2));
            r.x = l.x + l.w + root.labelGap;
        }
        const out = {};
        out[l.k] = l.x;
        out[r.k] = r.x;
        return out;
    }

    implicitWidth: 200
    implicitHeight: root.dotSize + (root.hasSun ? 4 + riseLabel.implicitHeight : 0)

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        y: (root.dotSize - height) / 2
        height: 4
        radius: 2
        color: Theme.surface0
    }

    // Daylight, then the part of it already behind the sun drawn over it.
    Repeater {
        model: root.daylight

        Rectangle {
            required property var modelData
            x: track.width * modelData[0]
            width: track.width * (modelData[1] - modelData[0])
            y: track.y
            height: track.height
            radius: track.radius
            color: Theme.surface2
        }
    }

    Repeater {
        model: root.travelled

        Rectangle {
            required property var modelData
            x: track.width * modelData[0]
            width: track.width * (modelData[1] - modelData[0])
            y: track.y
            height: track.height
            radius: track.radius
            color: Theme.yellow
        }
    }

    // Now. Ringed in the card's own colour so it reads as sitting on the line
    // rather than as part of it. Neutral before there is a sunrise to judge
    // by: a moon at noon would be a confident wrong answer.
    Rectangle {
        x: Math.max(0, Math.min(track.width - width, track.width * root.nowFrac - width / 2))
        y: 0
        width: root.dotSize
        height: root.dotSize
        radius: width / 2
        color: !root.hasSun ? Theme.subtext0 : root.daytime ? Theme.yellow : Theme.lavender
        border.width: 2
        border.color: Theme.mantle
    }

    Text {
        id: riseLabel
        visible: root.hasSun
        x: root.labelX.rise
        y: root.dotSize + 4
        // md-weather_sunset_up (U+F059C), as a surrogate pair. Material Design
        // rather than Weather Icons' sunrise, which is wider than its advance
        // and ran into the digits.
        textFormat: Text.StyledText
        text: '<font color="' + Theme.yellow + '">\udb81\udd9c</font> '
              + Qt.formatDateTime(new Date(root.sunrise * 1000), "h:mm AP")
        color: Theme.subtext0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }

    Text {
        id: setLabel
        visible: root.hasSun
        x: root.labelX.set
        y: root.dotSize + 4
        // md-weather_sunset_down (U+F059B).
        textFormat: Text.StyledText
        text: '<font color="' + Theme.peach + '">\udb81\udd9b</font> '
              + Qt.formatDateTime(new Date(root.sunset * 1000), "h:mm AP")
        color: Theme.subtext0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }
}
