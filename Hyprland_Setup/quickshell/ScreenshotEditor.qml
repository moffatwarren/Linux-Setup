pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

// SUPER+S screenshot editor, in place of swappy. hypr/scripts/screenshot.sh
// slurps and grims a region, then hands the file over with
// `qs ipc call screenshot open <png>`; Copy and Save render the annotated
// image to a file and hand it back to the same script, which owns the
// clipboard and the save directory.
//
// The same window as the other overlays -- dimmed backdrop, `base` card in a
// surface1 border -- but not an OverlayPanel: that frame is built around a
// filter box, and here the keyboard belongs to the text tool and the shortcuts.
//
// Drawing is two Canvases stacked at the capture's NATIVE size and scaled down
// to fit the screen, so a stroke is recorded in image pixels and the export is
// full resolution:
//
// - `paper` holds the capture plus every committed annotation. It only paints
//   when something is committed (incrementally) or undone (in full), because
//   it is an Image-backed canvas and every paint is a full texture upload.
// - `live` holds the one annotation being dragged out, cleared every frame.
//   It is FBO-backed for exactly that reason.
//
// Pixelate reads `paper`'s own pixels with getImageData, so it mosaics what is
// underneath it *including* earlier annotations, in the order they were drawn.
//
// The highlighter blends with what is under it too (multiply, then a screened
// tint -- see drawOp), which an empty `live` layer cannot show. So its preview
// copies `paper` once per stroke and blends onto that copy, and what is shown
// while dragging is what gets committed.
//
// Zoom (the wheel, on the pointer) enlarges the capture inside the same stage
// rather than growing the window, from the whole shot up to 1600%, by whole
// steps above 100% and sampled nearest-neighbour there, so every pixel of the
// capture is an even square. A right-drag or the floating scroll bars move it
// about. Zoomed in, Copy takes only what the stage shows, at the zoom it is
// shown at -- see viewCrop(). The same feature as WarrenTool's editor.
PanelWindow {
    id: root

    property bool open: false
    // file:// URL of the capture being edited.
    property string source: ""
    property int imgW: 0
    property int imgH: 0

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/screenshot.sh"
    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"

    // Tool, colour and size are kept between screenshots, as a paint program
    // keeps them between documents.
    property string tool: "pen"
    property string penColor: Theme.red
    property int size: 5

    // Every committed annotation, oldest first, and what Undo has taken off it.
    // An op is a plain object: { tool, color, width, ... } -- see drawOp().
    property var ops: []
    property var undone: []
    // The annotation being dragged out right now, or null.
    property var draft: null

    // The text tool's insertion point, in image pixels; null when not typing.
    property var textAt: null

    // "copy" / "save" while an export waits for `paper` to finish painting.
    property string pendingExport: ""

    // Zoom, in screen pixels per pixel of the capture, from `fit` (the whole
    // shot) up to 16. Above 1 the steps are whole numbers, so every pixel
    // shows as an even square: at 1.5 some would be one screen pixel wide and
    // some two. Logical pixels, strictly -- on a fractionally scaled monitor
    // the squares would not come out even, and every monitor here is scale 1.
    readonly property var zoomSteps: [0.25, 1 / 3, 0.5, 2 / 3, 1, 2, 3, 4, 6, 8, 12, 16]
    readonly property real maxZoom: 16
    // 0 is "fit", which then follows `fit` if the capture or the screen changes.
    property real zoomSet: 0
    readonly property real zoom: root.zoomSet > 0
                                 ? Math.max(root.fit, Math.min(root.maxZoom, root.zoomSet))
                                 : root.fit
    readonly property bool zoomed: root.zoom > root.fit

    // How far into the enlarged capture the stage's top-left corner is, in
    // screen pixels. Whole pixels, or the squares would not land on the
    // screen's evenly. panX/panY are what was asked for; viewX/viewY that,
    // clamped to the capture at the current zoom, which is what is drawn.
    property real panX: 0
    property real panY: 0
    readonly property int maxPanX: Math.max(0, Math.floor(root.imgW * root.zoom - stage.width))
    readonly property int maxPanY: Math.max(0, Math.floor(root.imgH * root.zoom - stage.height))
    readonly property int viewX: Math.max(0, Math.min(root.maxPanX, root.panX))
    readonly property int viewY: Math.max(0, Math.min(root.maxPanY, root.panY))
    // Right-dragging the capture around.
    property bool panning: false

    // The pixelate marquee being dragged, in image pixels, or null.
    property var marquee: null

    readonly property var tools: [
        { id: "pen",         glyph: "󰲶", key: Qt.Key_1 },          // md-pencil_outline
        { id: "highlighter", glyph: "󰙒", key: Qt.Key_2 }, // md-marker
        { id: "arrow",       glyph: "󰁜", key: Qt.Key_3 },          // md-arrow_top_right
        { id: "rect",        glyph: "󰹟", key: Qt.Key_4 },          // md-rectangle_outline
        { id: "ellipse",     glyph: "󰝦", key: Qt.Key_5 },          // md-circle_outline
        { id: "text",        glyph: "󰊄", key: Qt.Key_6 },          // md-format_text
        { id: "pixelate",    glyph: "󰄺", key: Qt.Key_7 }           // md-checkerboard
    ]

    // The pastel accents read on a dark capture and vanish on a white one, so
    // the last swatch is `crust` -- the one colour that shows on a light page.
    readonly property var swatches: [Theme.red, Theme.peach, Theme.yellow, Theme.green,
                                     Theme.blue, Theme.mauve, Theme.lavender, Theme.crust]

    // How far the capture is scaled down to fit on screen (never up): the
    // zoom that shows the whole shot, and the least there is.
    readonly property real fit: {
        if (root.imgW <= 0 || root.imgH <= 0) return 1;
        const sw = root.screen ? root.screen.width : 1920;
        const sh = root.screen ? root.screen.height : 1080;
        return Math.min(1, (sw - 160) / root.imgW,
                           (sh - 160 - card.chromeHeight) / root.imgH);
    }

    // Sizes are chosen on screen, so they are divided by the fit: a 5 looks
    // like a 5 however far a 4K capture had to be shrunk to be shown. By the
    // fit, not the zoom: a stroke is part of the picture, so zooming enlarges
    // it with everything else, and one drawn at 800% is the same size in the
    // capture as one drawn with the whole shot showing.
    readonly property real strokeWidth: Math.max(1, root.size / root.fit)
    // A highlighter has to cover a line of text, so it is far wider than the
    // pen at the same size: 21px at the default 5.
    readonly property real highlightWidth: (root.size * 3 + 6) / root.fit
    readonly property real textPx: (10 + root.size * 2) / root.fit
    readonly property real blockPx: Math.max(4, root.size * 3) / root.fit

    readonly property bool canUndo: root.ops.length > 0
    readonly property bool canRedo: root.undone.length > 0
    // Clear is itself an op (so Undo brings everything back); it is pointless
    // when nothing has been drawn since the start or the last clear.
    readonly property bool canClear: root.ops.length > 0
                                     && root.ops[root.ops.length - 1].tool !== "clear"

    screen: Hyprland.focusedMonitor?.screen ?? null

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: root.open

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-screenshot"
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive
                                           : WlrKeyboardFocus.None

    function openImage(path: string): void {
        if (root.source !== "") paper.unloadImage(root.source);
        root.ops = [];
        root.undone = [];
        root.draft = null;
        root.textAt = null;
        root.pendingExport = "";
        root.marquee = null;
        root.panning = false;
        root.zoomSet = 0;
        root.panX = 0;
        root.panY = 0;
        root.imgW = 0;
        root.imgH = 0;
        root.source = path.startsWith("file://") ? path : "file://" + path;
        // `probe` reports the size; `paper` is sized from it and then loads
        // the same URL for itself -- see onStatusChanged below.
        root.open = true;
        Qt.callLater(() => keys.forceActiveFocus());
    }

    function close(): void {
        root.open = false;
        root.textAt = null;
    }

    function setTool(id: string): void {
        root.commitText();
        root.tool = id;
    }

    function commit(op: var): void {
        root.ops = root.ops.concat([op]);
        root.undone = [];
        paper.queue.push(op);
        paper.requestPaint();
    }

    function undo(): void {
        root.commitText();
        if (!root.canUndo) return;
        root.undone = root.undone.concat([root.ops[root.ops.length - 1]]);
        root.ops = root.ops.slice(0, -1);
        paper.repaintAll();
    }

    function redo(): void {
        if (!root.canRedo) return;
        const op = root.undone[root.undone.length - 1];
        root.undone = root.undone.slice(0, -1);
        root.ops = root.ops.concat([op]);
        paper.queue.push(op);
        paper.requestPaint();
    }

    function clearAll(): void {
        root.commitText();
        if (root.canClear) root.commit({ tool: "clear" });
    }

    function commitText(): void {
        if (!root.textAt) return;
        const text = textEditor.text;
        const at = root.textAt;
        root.textAt = null;
        if (text.trim().length > 0)
            root.commit({ tool: "text", color: root.penColor, px: root.textPx,
                          x: at.x, y: at.y, text: text });
    }

    // Copy and Save both wait for `paper` to paint first, so a text box still
    // open when the button is pressed makes it into the file.
    function exportAs(kind: string): void {
        if (root.imgW <= 0) return;
        root.commitText();
        root.pendingExport = kind;
        paper.requestPaint();
    }

    function finishExport(): void {
        const kind = root.pendingExport;
        root.pendingExport = "";
        const out = root.runDir + "/screenshot-edited-" + Date.now() + ".png";
        if (!paper.save(out, Qt.size(root.imgW, root.imgH))) {
            Quickshell.execDetached(["notify-send", "-a", "Screenshot", "Screenshot failed",
                                     "Could not write " + out]);
            return;
        }
        Quickshell.execDetached([root.script, "--" + kind, out]
                                .concat(kind === "copy" ? root.viewCrop() : []));
        root.close();
    }

    // Zoomed in, Copy copies what the stage shows rather than the whole shot:
    // the part in view, at the zoom it is shown at -- or at full size between
    // fitting and 100%, where the stage shows it shrunk. Save always saves the
    // whole shot. screenshot.sh cuts the view out of the full-size export, from
    // what this returns: the crop of the capture covering the view, in its own
    // pixels, and above 100% the factor to enlarge that by (a square per
    // pixel) and the crop of the result the stage shows. That comes out pixel
    // for pixel as the screen does because the view's offset is a whole number
    // of screen pixels (panTo) and the stage sits on a whole pixel. Empty with
    // the whole shot showing, which copies it all, as before.
    function viewCrop(): var {
        if (!root.zoomed) return [];
        const z = root.zoom, w = stage.width, h = stage.height;
        const x0 = Math.floor(root.viewX / z), y0 = Math.floor(root.viewY / z);
        const x1 = Math.min(root.imgW, Math.ceil((root.viewX + w) / z));
        const y1 = Math.min(root.imgH, Math.ceil((root.viewY + h) / z));
        const crop = (x1 - x0) + "x" + (y1 - y0) + "+" + x0 + "+" + y0;
        if (z <= 1) return [crop];
        return [crop, String(z), w + "x" + h + "+" + (root.viewX - x0 * z) + "+" + (root.viewY - y0 * z)];
    }

    // ---- zoom --------------------------------------------------------------

    // Zooms to `next`, keeping the pixel of the capture at (ax, ay) -- a
    // point in the stage -- where it is on screen.
    function setZoom(next: real, ax: real, ay: real): void {
        if (root.imgW <= 0) return;
        const ix = (root.viewX + ax) / root.zoom;
        const iy = (root.viewY + ay) / root.zoom;
        next = Math.max(root.fit, Math.min(root.maxZoom, next));
        root.zoomSet = next > root.fit ? next : 0;
        root.panTo(ix * root.zoom - ax, iy * root.zoom - ay);
    }

    function panTo(x: real, y: real): void {
        root.panX = Math.round(Math.max(0, Math.min(root.maxPanX, x)));
        root.panY = Math.round(Math.max(0, Math.min(root.maxPanY, y)));
    }

    // The next step in or out from `from`. A step that would land just short
    // of fitting the whole shot fits it instead, and one barely past `from`
    // (a fit of 0.49 against the 0.5 step) is skipped.
    function stepZoom(from: real, dir: int): real {
        const steps = root.zoomSteps;
        if (dir > 0) {
            for (const s of steps) if (s > from * 1.05) return s;
            return root.maxZoom;
        }
        for (let i = steps.length - 1; i >= 0; i--)
            if (steps[i] < from / 1.05) return steps[i] < root.fit * 1.05 ? root.fit : steps[i];
        return root.fit;
    }

    // The toolbar's buttons and Ctrl+= / Ctrl+-: on the middle of the view.
    function zoomBy(dir: int): void {
        root.setZoom(root.stepZoom(root.zoom, dir), stage.width / 2, stage.height / 2);
    }

    function fitView(): void {
        root.setZoom(root.fit, 0, 0);
    }

    // Ctrl+= / Ctrl+- / Ctrl+0, for both key handlers, so they work while
    // typing too. Ahead of the bare + and -, which are the stroke size.
    function zoomKey(event: var): bool {
        if (!(event.modifiers & Qt.ControlModifier)) return false;
        if (event.key === Qt.Key_Equal || event.key === Qt.Key_Plus) root.zoomBy(1);
        else if (event.key === Qt.Key_Minus) root.zoomBy(-1);
        else if (event.key === Qt.Key_0) root.fitView();
        else return false;
        return true;
    }

    // ---- drawing ---------------------------------------------------------

    function drawOp(ctx: var, op: var): void {
        if (op.tool === "clear") {
            ctx.clearRect(0, 0, root.imgW, root.imgH);
            if (paper.isImageLoaded(root.source)) ctx.drawImage(root.source, 0, 0);
            return;
        }
        if (op.tool === "pixelate") {
            root.pixelate(ctx, op);
            return;
        }

        ctx.save();
        ctx.strokeStyle = op.color;
        ctx.fillStyle = op.color;
        ctx.lineWidth = op.width;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";

        switch (op.tool) {
        case "pen": {
            const p = op.points;
            if (p.length === 1) {
                ctx.beginPath();
                ctx.arc(p[0].x, p[0].y, op.width / 2, 0, Math.PI * 2);
                ctx.fill();
                break;
            }
            root.tracePath(ctx, p);
            ctx.stroke();
            break;
        }
        // Multiply, then a screened tint on top. Multiply alone is a real
        // highlighter on a light page -- white takes the colour, black text
        // stays black -- and does nothing at all on a dark one, where the
        // tint is what shows. Plain transparency, the obvious version, turns
        // a pastel on white into a faint cream and greys the text under it.
        // Each pass is one stroke() of the whole path, so the stroke does not
        // darken where it crosses itself.
        case "highlighter":
            ctx.lineCap = "butt";
            root.tracePath(ctx, op.points);
            ctx.globalCompositeOperation = "qt-multiply";
            ctx.stroke();
            ctx.globalCompositeOperation = "qt-screen";
            ctx.globalAlpha = 0.35;
            ctx.stroke();
            break;
        case "arrow": {
            const a = Math.atan2(op.y2 - op.y1, op.x2 - op.x1);
            const head = op.width * 3 + 8;
            // The shaft stops inside the head, or its round cap pokes out of
            // the point at large sizes.
            ctx.beginPath();
            ctx.moveTo(op.x1, op.y1);
            ctx.lineTo(op.x2 - Math.cos(a) * head * 0.7, op.y2 - Math.sin(a) * head * 0.7);
            ctx.stroke();
            ctx.beginPath();
            ctx.moveTo(op.x2, op.y2);
            ctx.lineTo(op.x2 - head * Math.cos(a - Math.PI / 7), op.y2 - head * Math.sin(a - Math.PI / 7));
            ctx.lineTo(op.x2 - head * Math.cos(a + Math.PI / 7), op.y2 - head * Math.sin(a + Math.PI / 7));
            ctx.closePath();
            ctx.fill();
            break;
        }
        case "rect": {
            const r = root.norm(op);
            ctx.strokeRect(r.x, r.y, r.w, r.h);
            break;
        }
        case "ellipse": {
            const r = root.norm(op);
            ctx.beginPath();
            ctx.ellipse(r.x, r.y, r.w, r.h);
            ctx.stroke();
            break;
        }
        case "text":
            ctx.font = "bold " + Math.round(op.px) + "px \"" + Theme.fontFamily + "\"";
            ctx.textBaseline = "top";
            ctx.fillText(op.text, op.x, op.y);
            break;
        }
        ctx.restore();
    }

    // Each block takes the average of five samples (its centre and the centre
    // of each quarter) rather than every pixel: a mosaic over a large region
    // is then a few thousand reads, not millions, and looks the same.
    function pixelate(ctx: var, op: var): void {
        const r = root.norm(op);
        const x = Math.max(0, Math.floor(r.x));
        const y = Math.max(0, Math.floor(r.y));
        const w = Math.min(root.imgW, Math.ceil(r.x + r.w)) - x;
        const h = Math.min(root.imgH, Math.ceil(r.y + r.h)) - y;
        if (w <= 0 || h <= 0) return;
        const b = Math.max(2, Math.round(op.block));
        const d = ctx.getImageData(x, y, w, h).data;
        const offs = [[0.5, 0.5], [0.25, 0.25], [0.75, 0.25], [0.25, 0.75], [0.75, 0.75]];
        for (let by = 0; by < h; by += b) {
            const bh = Math.min(b, h - by);
            for (let bx = 0; bx < w; bx += b) {
                const bw = Math.min(b, w - bx);
                let cr = 0, cg = 0, cb = 0;
                for (const o of offs) {
                    const i = ((by + Math.floor(bh * o[1])) * w + bx + Math.floor(bw * o[0])) * 4;
                    cr += d[i]; cg += d[i + 1]; cb += d[i + 2];
                }
                ctx.fillStyle = "rgb(" + Math.round(cr / 5) + "," + Math.round(cg / 5) + ","
                                + Math.round(cb / 5) + ")";
                ctx.fillRect(x + bx, y + by, bw, bh);
            }
        }
    }

    // Through the midpoints, with each sample as the control point: a smooth
    // curve rather than a polyline of mouse samples.
    function tracePath(ctx: var, p: var): void {
        ctx.beginPath();
        ctx.moveTo(p[0].x, p[0].y);
        for (let i = 1; i < p.length - 1; i++)
            ctx.quadraticCurveTo(p[i].x, p[i].y,
                                 (p[i].x + p[i + 1].x) / 2, (p[i].y + p[i + 1].y) / 2);
        ctx.lineTo(p[p.length - 1].x, p[p.length - 1].y);
    }

    function norm(op: var): var {
        return { x: Math.min(op.x1, op.x2), y: Math.min(op.y1, op.y2),
                 w: Math.abs(op.x2 - op.x1), h: Math.abs(op.y2 - op.y1) };
    }

    // ---- window ----------------------------------------------------------

    // Only reports the capture's size; nothing draws it.
    Image {
        id: probe
        visible: false
        source: root.source
        onStatusChanged: {
            if (status !== Image.Ready) return;
            root.imgW = implicitWidth;
            root.imgH = implicitHeight;
            paper.loadImage(root.source);
            paper.repaintAll();
        }
    }

    // Clicking the backdrop does nothing, unlike the other overlays: one
    // stray click is not worth losing the annotations to.
    Rectangle {
        anchors.fill: parent
        color: "#cc11111b"

        MouseArea { anchors.fill: parent }
    }

    // Keyboard shortcuts. The text box takes focus while it is up, and hands
    // it back here when it commits.
    Item {
        id: keys
        focus: true

        Keys.onPressed: event => {
            const ctrl = event.modifiers & Qt.ControlModifier;
            const shift = event.modifiers & Qt.ShiftModifier;
            if (root.zoomKey(event)) {}
            else if (event.key === Qt.Key_Escape) root.close();
            else if (ctrl && event.key === Qt.Key_Z) shift ? root.redo() : root.undo();
            else if (ctrl && event.key === Qt.Key_Y) root.redo();
            else if (ctrl && event.key === Qt.Key_C) root.exportAs("copy");
            else if (ctrl && event.key === Qt.Key_S) root.exportAs("save");
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.exportAs("copy");
            else if (event.key === Qt.Key_Delete) root.clearAll();
            else if (event.key === Qt.Key_Minus) root.size = Math.max(1, root.size - 1);
            else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) root.size = Math.min(20, root.size + 1);
            else {
                const hit = root.tools.find(t => t.key === event.key);
                if (!hit) return;
                root.setTool(hit.id);
            }
            event.accepted = true;
        }
    }

    Rectangle {
        id: card

        readonly property int pad: 14
        // Everything but the image: title row, toolbar and the gaps around them.
        readonly property int chromeHeight: titleRow.height + toolbar.height + pad * 3 + 10

        // Centred on a whole pixel, as the stage inside it is: half a pixel
        // out and the zoomed squares come out uneven.
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Math.max(toolbar.implicitWidth, stage.width) + pad * 2
        height: chromeHeight + Math.max(stage.height, 120)
        radius: 16
        color: Theme.base
        border.width: 1
        border.color: Theme.surface1

        MouseArea { anchors.fill: parent }

        Item {
            id: titleRow

            anchors { top: parent.top; left: parent.left; right: parent.right; margins: card.pad }
            height: 22

            Text {
                id: titleGlyph
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "󰒉" // md-selection
                color: Theme.mauve
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
            }

            Text {
                id: titleText
                anchors.left: titleGlyph.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "Screenshot"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                anchors.left: titleText.right
                anchors.leftMargin: 12
                anchors.right: closeButton.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.imgW + " × " + root.imgH
                      + "     1–7 tools   Wheel zoom   Right-drag pan   Ctrl+Z undo"
                      + "   Ctrl+C / Enter copy   Ctrl+S save   Esc close"
                color: Theme.overlay0
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }

            ToolButton {
                id: closeButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 22
                glyph: "󰅖" // md-close
                hoverColor: Theme.red
                onClicked: root.close()
            }
        }

        Rectangle {
            id: toolbar

            anchors { top: titleRow.bottom; topMargin: 10; left: parent.left; right: parent.right }
            anchors.leftMargin: card.pad
            anchors.rightMargin: card.pad
            height: 44
            implicitWidth: leftGroup.implicitWidth + rightGroup.implicitWidth + 40
            radius: 10
            color: Theme.mantle

            Row {
                id: leftGroup

                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Repeater {
                    model: root.tools

                    ToolButton {
                        required property var modelData
                        glyph: modelData.glyph
                        selected: root.tool === modelData.id
                        onClicked: root.setTool(modelData.id)
                    }
                }

                Separator {}

                Repeater {
                    model: root.swatches

                    Item {
                        id: swatch

                        required property string modelData
                        readonly property bool selected: root.penColor === modelData

                        width: 26
                        height: 32

                        // The selected swatch wears a ring with a gap of
                        // card colour between it and the dot.
                        Rectangle {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            radius: 11
                            color: "transparent"
                            border.width: 2
                            border.color: swatch.selected ? Theme.text : "transparent"
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: swatch.selected ? 14 : 13
                            height: width
                            radius: width / 2
                            color: swatch.modelData
                            // crust is the card's own colour; outline it.
                            border.width: swatch.modelData === Theme.crust ? 1 : 0
                            border.color: Theme.overlay0
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.penColor = swatch.modelData
                        }
                    }
                }

                Separator {}

                ToolButton {
                    glyph: "󰍴" // md-minus
                    enabled: root.size > 1
                    onClicked: root.size = Math.max(1, root.size - 1)
                }

                Text {
                    width: 24
                    height: 32
                    text: root.size
                    color: Theme.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize

                    // The wheel steps it too, the way it steps the volume.
                    WheelHandler {
                        onWheel: event => root.size = Math.max(1, Math.min(20,
                                                     root.size + (event.angleDelta.y > 0 ? 1 : -1)))
                    }
                }

                ToolButton {
                    glyph: "󰐕" // md-plus
                    enabled: root.size < 20
                    onClicked: root.size = Math.min(20, root.size + 1)
                }

                Separator {}

                ToolButton {
                    glyph: "󰕍" // md-undo_variant
                    enabled: root.canUndo || root.textAt !== null
                    onClicked: root.undo()
                }

                ToolButton {
                    glyph: "󰑏" // md-redo_variant
                    enabled: root.canRedo
                    onClicked: root.redo()
                }

                ToolButton {
                    glyph: "󰧧" // md-delete_outline
                    enabled: root.canClear
                    hoverColor: Theme.red
                    onClicked: root.clearAll()
                }

                Separator {}

                ToolButton {
                    glyph: "󰛬" // md-magnify_minus_outline
                    enabled: root.zoomed
                    onClicked: root.zoomBy(-1)
                }

                // The zoom; a click on it fits the whole shot again (Ctrl+0).
                Rectangle {
                    width: 50
                    height: 32
                    radius: 7
                    color: zoomMouse.containsMouse && root.zoomed ? Theme.surface0 : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: Math.round(root.zoom * 100) + "%"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    MouseArea {
                        id: zoomMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root.zoomed ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.fitView()
                    }
                }

                ToolButton {
                    glyph: "󰛭" // md-magnify_plus_outline
                    enabled: root.imgW > 0 && root.zoom < root.maxZoom
                    onClicked: root.zoomBy(1)
                }
            }

            Row {
                id: rightGroup

                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                TextButton {
                    glyph: "󰮏" // md-download_outline
                    label: "Save"
                    onClicked: root.exportAs("save")
                }

                TextButton {
                    glyph: "󰆏" // md-content_copy
                    label: "Copy to clipboard"
                    primary: true
                    onClicked: root.exportAs("copy")
                }
            }
        }

        // The image area: `mantle`, so a capture of a dark window still has
        // an edge, with the scaled stage centred in it.
        Rectangle {
            anchors { top: toolbar.bottom; topMargin: card.pad; bottom: parent.bottom; bottomMargin: card.pad }
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: card.pad
            anchors.rightMargin: card.pad
            radius: 6
            color: Theme.mantle

            // The wheel zooms anywhere in here, so the capture need not be
            // aimed at, and a right-drag moves it about. It lies under the
            // stage, which lets both through: the drawing MouseArea takes only
            // the left button and has no wheel handler.
            MouseArea {
                id: panArea

                // Wheel movement short of a whole notch.
                property real rest: 0
                // Where a right-drag began, and the view's offset then.
                property point grabAt
                property point startView

                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                cursorShape: root.panning ? Qt.ClosedHandCursor : Qt.ArrowCursor

                // On the pointer: what is under it stays under it.
                onWheel: wheel => {
                    // The drag holds on to the offset it started from.
                    if (root.panning || wheel.angleDelta.y === 0) return;
                    // A touchpad sends a notch in slivers; they add up to one.
                    if ((panArea.rest > 0) !== (wheel.angleDelta.y > 0)) panArea.rest = 0;
                    panArea.rest += wheel.angleDelta.y;
                    const notches = Math.trunc(panArea.rest / 120);
                    if (notches === 0) return;
                    panArea.rest -= notches * 120;
                    let next = root.zoom;
                    for (let i = 0; i < Math.abs(notches); i++) next = root.stepZoom(next, notches);
                    const p = panArea.mapToItem(stage, wheel.x, wheel.y);
                    root.setZoom(next, Math.max(0, Math.min(stage.width, p.x)),
                                       Math.max(0, Math.min(stage.height, p.y)));
                }

                onPressed: mouse => {
                    if (root.draft || (root.maxPanX <= 0 && root.maxPanY <= 0)) {
                        mouse.accepted = false;
                        return;
                    }
                    root.panning = true;
                    panArea.grabAt = Qt.point(mouse.x, mouse.y);
                    panArea.startView = Qt.point(root.viewX, root.viewY);
                }
                onPositionChanged: mouse => {
                    if (root.panning)
                        root.panTo(panArea.startView.x - (mouse.x - panArea.grabAt.x),
                                   panArea.startView.y - (mouse.y - panArea.grabAt.y));
                }
                onReleased: root.panning = false
                onCanceled: root.panning = false
            }

            // The size of the whole shot at every zoom: zooming enlarges the
            // capture inside it rather than the window.
            Item {
                id: stage

                // On a whole pixel, as the view's offset is.
                x: Math.round((parent.width - width) / 2)
                y: Math.round((parent.height - height) / 2)
                width: Math.round(root.imgW * root.fit)
                height: Math.round(root.imgH * root.fit)
                clip: true

                // Native-size layers, scaled as one. Everything inside is in
                // image pixels, including the MouseArea's coordinates.
                Item {
                    id: layers

                    x: -root.viewX
                    y: -root.viewY
                    width: root.imgW
                    height: root.imgH
                    scale: root.zoom
                    transformOrigin: Item.TopLeft

                    Canvas {
                        id: paper

                        // Ops waiting to be drawn on top of what is there.
                        property var queue: []
                        property bool full: false

                        function repaintAll(): void {
                            paper.full = true;
                            paper.queue = [];
                            paper.requestPaint();
                        }

                        anchors.fill: parent
                        // Crisp squares from 100% up, smooth shrinking below.
                        smooth: root.zoom < 1
                        renderTarget: Canvas.Image
                        onImageLoaded: paper.repaintAll()

                        onPaint: {
                            const ctx = getContext("2d");
                            if (paper.full) {
                                paper.full = false;
                                ctx.clearRect(0, 0, width, height);
                                if (isImageLoaded(root.source)) ctx.drawImage(root.source, 0, 0);
                                for (const op of root.ops) root.drawOp(ctx, op);
                            } else {
                                for (const op of paper.queue) root.drawOp(ctx, op);
                            }
                            paper.queue = [];
                            // A highlighter being dragged previews against
                            // what was here, which has just changed.
                            if (root.draft && root.draft.tool === "highlighter") {
                                live.backdrop = null;
                                live.requestPaint();
                            }
                            // Not onPainted: that is not emitted for a paint
                            // that drew nothing new, which is the usual export.
                            if (root.pendingExport !== "") Qt.callLater(root.finishExport);
                        }
                    }

                    Canvas {
                        id: live

                        // A copy of `paper`, taken when a highlighter stroke
                        // starts and dropped when it ends.
                        property var backdrop: null

                        anchors.fill: parent
                        smooth: root.zoom < 1
                        renderTarget: Canvas.FramebufferObject
                        renderStrategy: Canvas.Cooperative

                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            const op = root.draft;
                            if (!op) return;
                            if (op.tool === "highlighter") {
                                // Multiply and screen blend with what is under
                                // them, and this layer is empty -- so the stroke's
                                // shape is filled with a copy of `paper` first and
                                // blended onto that, which makes the preview the
                                // committed result exactly. Clipped to the stroke's
                                // box, so only that much of the copy is drawn.
                                if (!live.backdrop)
                                    live.backdrop = paper.getContext("2d")
                                                         .getImageData(0, 0, root.imgW, root.imgH);
                                let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
                                for (const p of op.points) {
                                    x0 = Math.min(x0, p.x); y0 = Math.min(y0, p.y);
                                    x1 = Math.max(x1, p.x); y1 = Math.max(y1, p.y);
                                }
                                ctx.save();
                                ctx.beginPath();
                                ctx.rect(x0 - op.width, y0 - op.width,
                                         x1 - x0 + op.width * 2, y1 - y0 + op.width * 2);
                                ctx.clip();
                                ctx.lineWidth = op.width;
                                ctx.lineCap = "butt";
                                ctx.lineJoin = "round";
                                root.tracePath(ctx, op.points);
                                ctx.stroke();
                                ctx.globalCompositeOperation = "source-in";
                                ctx.drawImage(live.backdrop, 0, 0);
                                ctx.restore();
                            }
                            // Pixelate's drag is the marquee below.
                            if (op.tool !== "pixelate") root.drawOp(ctx, op);
                        }
                    }

                    // A mosaic is drawn for real only on release; the drag
                    // shows the region it will cover. A Rectangle, not lines on
                    // `live`: that canvas is at the capture's resolution, so a
                    // one-screen-pixel outline on it at 1600% would be a faint
                    // 16px band. Here it stays one screen pixel at any zoom.
                    Rectangle {
                        visible: root.marquee !== null
                        x: root.marquee ? root.marquee.x : 0
                        y: root.marquee ? root.marquee.y : 0
                        width: root.marquee ? root.marquee.w : 0
                        height: root.marquee ? root.marquee.h : 0
                        color: "#5911111b"
                        border.color: Theme.text
                        border.width: 1 / root.zoom
                        // Or the width is rounded in this item's own units,
                        // where 1/16 is 0, and no border is drawn at all.
                        border.pixelAligned: false
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: root.panning ? Qt.ClosedHandCursor
                                   : root.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor

                        onPressed: mouse => {
                            if (root.panning) {
                                mouse.accepted = false;
                                return;
                            }
                            root.commitText();
                            const x = mouse.x, y = mouse.y;
                            if (root.tool === "text") {
                                textEditor.text = "";
                                root.textAt = { x: x, y: y };
                                textEditor.forceActiveFocus();
                                return;
                            }
                            live.backdrop = null;
                            if (root.tool === "pen")
                                root.draft = { tool: "pen", color: root.penColor, width: root.strokeWidth,
                                               points: [{ x: x, y: y }] };
                            else if (root.tool === "highlighter")
                                root.draft = { tool: "highlighter", color: root.penColor,
                                               width: root.highlightWidth, points: [{ x: x, y: y }],
                                               tipKept: true };
                            else
                                root.draft = { tool: root.tool, color: root.penColor, width: root.strokeWidth,
                                               block: root.blockPx, x1: x, y1: y, x2: x, y2: y };
                            if (root.tool === "pixelate") root.marquee = root.norm(root.draft);
                            live.requestPaint();
                        }

                        onPositionChanged: mouse => {
                            const op = root.draft;
                            if (!op) return;
                            const x = Math.max(0, Math.min(root.imgW, mouse.x));
                            const y = Math.max(0, Math.min(root.imgH, mouse.y));
                            const p = op.points;
                            // The highlighter's last point follows the cursor, and
                            // is kept only once it is half a stroke-width from the
                            // kept point before it. Each preview frame strokes the
                            // whole path three times: on a 4K capture, keeping
                            // every sample cost ~23ms a frame by the 120th and kept
                            // climbing, where thinned a 3000px drag stays at 7.8ms,
                            // the pen's ~7. It also irons out the hand's wobble,
                            // which suits a marker.
                            if (op.tool === "highlighter") {
                                if (op.tipKept) p.push({ x: x, y: y });
                                else p[p.length - 1] = { x: x, y: y };
                                op.tipKept = Math.hypot(x - p[p.length - 2].x,
                                                        y - p[p.length - 2].y) >= op.width / 2;
                            } else if (p) p.push({ x: x, y: y });
                            else { op.x2 = x; op.y2 = y; }
                            if (op.tool === "pixelate") root.marquee = root.norm(op);
                            live.requestPaint();
                        }

                        onReleased: {
                            const op = root.draft;
                            root.draft = null;
                            root.marquee = null;
                            live.backdrop = null;
                            live.requestPaint();
                            if (!op) return;
                            // A click with a shape tool or the highlighter draws
                            // nothing; with the pen it is a dot, which is what a
                            // click means there.
                            // A third point means it moved half a width already, so
                            // only a two-point stroke can be a click -- and a loop
                            // ending where it began is not one.
                            if (op.tool === "highlighter") {
                                const p = op.points;
                                if (p.length < 2 || (p.length === 2
                                    && Math.hypot(p[1].x - p[0].x, p[1].y - p[0].y) < 2)) return;
                            } else if (op.tool !== "pen"
                                       && Math.abs(op.x2 - op.x1) < 2 && Math.abs(op.y2 - op.y1) < 2) return;
                            root.commit(op);
                        }
                    }

                    // The text tool types into a real TextInput laid over the
                    // image at the size the text will be drawn, so what you see
                    // while typing is what gets committed.
                    TextInput {
                        id: textEditor

                        visible: root.textAt !== null
                        x: root.textAt ? root.textAt.x : 0
                        y: root.textAt ? root.textAt.y : 0
                        color: root.penColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(root.textPx)
                        font.bold: true
                        cursorVisible: visible
                        selectionColor: Theme.surface2

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                root.commitText();
                                keys.forceActiveFocus();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.textAt = null;
                                keys.forceActiveFocus();
                                event.accepted = true;
                            } else if (root.zoomKey(event)) {
                                event.accepted = true;
                            }
                        }
                    }
                }
            }

            // Scroll bars floating over the stage's right and bottom edges
            // rather than taking room beside it, so the stage is the same size
            // at every zoom. They show only zoomed in; the corner is left free.
            PanBar {
                vertical: true
                x: stage.x + stage.width - width
                y: stage.y
                width: 10
                height: stage.height - 10
                value: root.viewY
                range: root.maxPanY
                page: stage.height
                onScrolled: to => root.panTo(root.viewX, to)
            }

            PanBar {
                x: stage.x
                y: stage.y + stage.height - height
                width: stage.width - 10
                height: 10
                value: root.viewX
                range: root.maxPanX
                page: stage.width
                onScrolled: to => root.panTo(to, root.viewY)
            }
        }
    }

    // ---- toolbar pieces ----------------------------------------------------

    component Separator: Rectangle {
        width: 13
        height: 32
        color: "transparent"

        Rectangle {
            anchors.centerIn: parent
            width: 1
            height: 18
            color: Theme.surface1
        }
    }

    // An icon button: `selected` is the active tool's surface1 chip, and a
    // disabled one is dimmed to overlay0 and inert.
    component ToolButton: Rectangle {
        id: tb

        property string glyph: ""
        property bool selected: false
        property string hoverColor: Theme.text

        signal clicked

        width: 32
        height: 32
        radius: 7
        color: tb.selected ? Theme.surface1 : (tbMouse.containsMouse && tb.enabled ? Theme.surface0 : "transparent")
        border.width: tb.selected ? 1 : 0
        border.color: Theme.lavender

        Text {
            anchors.centerIn: parent
            text: tb.glyph
            color: !tb.enabled ? Theme.surface2
                 : (tbMouse.containsMouse ? tb.hoverColor : Theme.text)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 4
        }

        MouseArea {
            id: tbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: tb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (tb.enabled) tb.clicked()
        }
    }

    // A thin scroll bar for the zoomed capture: a rounded thumb, and a click
    // either side of it pages, as on any scroll bar. `value` and `range` are
    // the view's offset and how far it can go, `page` the stage's length, all
    // in screen pixels. It only reports where to go; the editor moves the view.
    component PanBar: Item {
        id: bar

        property bool vertical: false
        property real value: 0
        property real range: 0
        property real page: 0

        signal scrolled(real to)

        readonly property real track: bar.vertical ? bar.height : bar.width
        readonly property real thumbLength: Math.min(bar.track,
                                                     Math.max(24, bar.track * bar.page / (bar.page + bar.range)))
        readonly property real thumbAt: bar.range > 0 ? (bar.track - bar.thumbLength) * bar.value / bar.range : 0
        readonly property real pointer: bar.vertical ? barMouse.mouseY : barMouse.mouseX
        readonly property bool overThumb: barMouse.containsMouse && bar.pointer >= bar.thumbAt
                                          && bar.pointer < bar.thumbAt + bar.thumbLength

        visible: bar.range > 0

        MouseArea {
            id: barMouse

            // Where along the thumb it was taken, or -1 for a page click.
            property real held: -1

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor

            onPressed: mouse => {
                const at = bar.vertical ? mouse.y : mouse.x;
                if (at >= bar.thumbAt && at < bar.thumbAt + bar.thumbLength) {
                    barMouse.held = at - bar.thumbAt;
                } else {
                    barMouse.held = -1;
                    bar.scrolled(bar.value + (at < bar.thumbAt ? -bar.page : bar.page));
                }
            }
            onPositionChanged: mouse => {
                if (barMouse.held < 0 || !barMouse.pressed) return;
                const at = (bar.vertical ? mouse.y : mouse.x) - barMouse.held;
                bar.scrolled(at / Math.max(1, bar.track - bar.thumbLength) * bar.range);
            }
            onReleased: barMouse.held = -1
            onCanceled: barMouse.held = -1
        }

        Rectangle {
            x: bar.vertical ? 2 : bar.thumbAt + 2
            y: bar.vertical ? bar.thumbAt + 2 : 2
            width: (bar.vertical ? bar.width : bar.thumbLength) - 4
            height: (bar.vertical ? bar.thumbLength : bar.height) - 4
            radius: 3
            color: Theme.subtext0
            border.width: 1
            border.color: Theme.crust
            opacity: barMouse.held >= 0 ? 1 : (bar.overThumb ? 0.85 : 0.6)
        }
    }

    // Save is a quiet button, Copy the filled mauve one: copying is what a
    // screenshot is taken for nine times in ten, so it is the one to aim at.
    component TextButton: Rectangle {
        id: btn

        property string glyph: ""
        property string label: ""
        property bool primary: false

        signal clicked

        width: btnRow.implicitWidth + 24
        height: 32
        radius: 7
        color: btn.primary ? (btnMouse.containsMouse ? Theme.lavender : Theme.mauve)
                           : (btnMouse.containsMouse ? Theme.surface0 : "transparent")

        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.glyph
                color: btn.primary ? Theme.crust : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: btn.label
                color: btn.primary ? Theme.crust : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
        }

        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }
}
