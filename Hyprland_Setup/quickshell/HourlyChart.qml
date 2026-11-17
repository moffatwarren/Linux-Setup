import QtQuick
import QtQuick.Shapes

// The next 24 hours under the current reading in ForecastCard: the
// temperature as a line with a fading fill under it, and every third hour
// marked with its temperature above the line and, below it, the condition's
// glyph over the time -- the same glyphs the seven-day table uses, from
// WeatherCodes, with a moon in place of the sun at night.
//
// The line runs through every hour; only the labels are every third, because
// eight columns is what fits a time ("11pm") per column in the card's width.
Item {
    id: root

    // [{ t, code, temp, day }], hourly, from WeatherService.
    property var hours: []
    // The reading for now. The first column shows it in place of the current
    // hour's forecast, so it is labelled "Now" and agrees with the big
    // temperature above it rather than being a forecast for an hour that is
    // already partly over.
    property var current: ({})
    // Unix seconds. ForecastCard's half-minute tick, so an open menu drops an
    // hour once it is over.
    property double nowSec: Date.now() / 1000
    property string unit: ""

    readonly property int step: 3
    readonly property int columns: 8

    // Hours not yet over, from the current one. A cache can outlive an hour
    // or two when the network is down; the past is dropped, not drawn.
    readonly property var upcoming: {
        const out = [];
        const hs = root.hours || [];
        const cur = root.current || {};
        for (let i = 0; i < hs.length; i++) {
            const h = hs[i];
            if (h.temp !== undefined && h.t + 3600 > root.nowSec) out.push(h);
        }
        if (out.length > 0 && cur.temp !== undefined) {
            const now = Object.assign({}, out[0]);
            now.temp = cur.temp;
            if (cur.code !== undefined) now.code = cur.code;
            if (cur.day !== undefined) now.day = cur.day;
            out[0] = now;
        }
        return out;
    }

    // The hours the eight columns span, plus one past the last column so the
    // line runs on to the right edge instead of stopping at its centre.
    readonly property var shown: root.upcoming.slice(0, root.columns * root.step + 1)

    readonly property real colW: root.width / root.columns
    readonly property int labelH: 14
    readonly property int chartTop: labelH + 2
    readonly property int chartH: 34
    readonly property int chartBottom: chartTop + chartH

    // The vertical scale is the span of what is drawn, but never less than a
    // few degrees: a day that moves by one degree should look flat, not like
    // a cliff.
    readonly property var range: {
        let lo = Infinity, hi = -Infinity;
        for (let i = 0; i < root.shown.length; i++) {
            lo = Math.min(lo, root.shown[i].temp);
            hi = Math.max(hi, root.shown[i].temp);
        }
        if (!isFinite(lo)) return { lo: 0, hi: 1 };
        const minSpan = root.unit === "F" ? 7 : 4;
        if (hi - lo < minSpan) {
            const mid = (hi + lo) / 2;
            lo = mid - minSpan / 2;
            hi = mid + minSpan / 2;
        }
        return { lo: lo, hi: hi };
    }

    function xAt(i) { return (i / root.step + 0.5) * root.colW; }
    function yAt(temp) {
        const f = (temp - root.range.lo) / (root.range.hi - root.range.lo);
        return root.chartTop + (1 - f) * root.chartH;
    }

    // The line, held flat from the left edge to the first column's centre.
    readonly property var linePoints: {
        if (root.shown.length === 0 || root.width <= 0) return [];
        const pts = [Qt.point(0, root.yAt(root.shown[0].temp))];
        for (let i = 0; i < root.shown.length; i++)
            pts.push(Qt.point(root.xAt(i), root.yAt(root.shown[i].temp)));
        // Short of a full day (a stale cache), hold the last reading to the edge.
        const last = pts[pts.length - 1];
        if (last.x < root.width) pts.push(Qt.point(root.width, last.y));
        return pts;
    }

    readonly property var fillPoints: {
        if (root.linePoints.length === 0) return [];
        const pts = root.linePoints.slice();
        pts.push(Qt.point(pts[pts.length - 1].x, root.chartBottom + 2));
        pts.push(Qt.point(0, root.chartBottom + 2));
        return pts;
    }

    // The labelled hours: every third, as many columns as there are hours for.
    readonly property var marks: {
        const out = [];
        for (let c = 0; c < root.columns; c++) {
            const i = c * root.step;
            if (i >= root.upcoming.length) break;
            out.push({ i: i, h: root.upcoming[i] });
        }
        return out;
    }

    visible: root.upcoming.length >= 2
    implicitWidth: root.columns * 34
    implicitHeight: root.chartBottom + 6 + 18 + 13

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.chartBottom + 2
        clip: true

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // The fill fades out downwards rather than sitting at one alpha: a
            // flat translucent yellow on the card's near-black reads as khaki,
            // the trap SunTrack's daylight fell into.
            ShapePath {
                strokeColor: "transparent"
                fillGradient: LinearGradient {
                    x1: 0; y1: root.chartTop
                    x2: 0; y2: root.chartBottom + 2
                    GradientStop { position: 0; color: "#55" + Theme.yellow.substring(1) }
                    GradientStop { position: 1; color: "#00" + Theme.yellow.substring(1) }
                }
                PathPolyline { path: root.fillPoints }
            }

            ShapePath {
                strokeColor: Theme.yellow
                strokeWidth: 2
                fillColor: "transparent"
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathPolyline { path: root.linePoints }
            }
        }
    }

    Repeater {
        model: root.marks

        Item {
            id: mark
            required property var modelData
            required property int index

            readonly property var cond: WeatherCodes.condition(modelData.h.code, modelData.h.day)

            x: root.xAt(modelData.i) - root.colW / 2
            width: root.colW
            height: root.height

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.yAt(mark.modelData.h.temp) - height - 1
                text: Math.round(mark.modelData.h.temp) + "°"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                font.bold: mark.index === 0
            }

            // The condition sits on top of the time, as asked: what it will
            // be like, then when.
            Text {
                id: glyph
                anchors.horizontalCenter: parent.horizontalCenter
                y: root.chartBottom + 6
                text: mark.cond.icon
                color: mark.cond.color
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: glyph.bottom
                anchors.topMargin: 1
                text: mark.index === 0 ? "Now"
                    : Qt.formatDateTime(new Date(mark.modelData.h.t * 1000), "hap")
                color: mark.index === 0 ? Theme.lavender : Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                font.bold: mark.index === 0
            }
        }
    }
}
