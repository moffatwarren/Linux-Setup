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

    readonly property var tools: [
        { id: "pen",      glyph: "󰲶", key: Qt.Key_1 }, // md-pencil_outline
        { id: "arrow",    glyph: "󰁜", key: Qt.Key_2 }, // md-arrow_top_right
        { id: "rect",     glyph: "󰹟", key: Qt.Key_3 }, // md-rectangle_outline
        { id: "ellipse",  glyph: "󰝦", key: Qt.Key_4 }, // md-circle_outline
        { id: "text",     glyph: "󰊄", key: Qt.Key_5 }, // md-format_text
        { id: "pixelate", glyph: "󰄺", key: Qt.Key_6 }  // md-checkerboard
    ]

    // The pastel accents read on a dark capture and vanish on a white one, so
    // the last swatch is `crust` -- the one colour that shows on a light page.
    readonly property var swatches: [Theme.red, Theme.peach, Theme.yellow, Theme.green,
                                     Theme.blue, Theme.mauve, Theme.lavender, Theme.crust]

    // How far the capture is scaled down to fit on screen (never up).
    readonly property real fit: {
        if (root.imgW <= 0 || root.imgH <= 0) return 1;
        const sw = root.screen ? root.screen.width : 1920;
        const sh = root.screen ? root.screen.height : 1080;
        return Math.min(1, (sw - 160) / root.imgW,
                           (sh - 160 - card.chromeHeight) / root.imgH);
    }

    // Sizes are chosen on screen, so they are divided by the fit: a 5 looks
    // like a 5 however far a 4K capture had to be shrunk to be shown.
    readonly property real strokeWidth: Math.max(1, root.size / root.fit)
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
        Quickshell.execDetached([root.script, "--" + kind, out]);
        root.close();
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
            ctx.beginPath();
            if (p.length === 1) {
                ctx.arc(p[0].x, p[0].y, op.width / 2, 0, Math.PI * 2);
                ctx.fill();
                break;
            }
            // Through the midpoints, with each sample as the control point:
            // a smooth curve rather than a polyline of mouse samples.
            ctx.moveTo(p[0].x, p[0].y);
            for (let i = 1; i < p.length - 1; i++)
                ctx.quadraticCurveTo(p[i].x, p[i].y,
                                     (p[i].x + p[i + 1].x) / 2, (p[i].y + p[i + 1].y) / 2);
            ctx.lineTo(p[p.length - 1].x, p[p.length - 1].y);
            ctx.stroke();
            break;
        }
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
            if (event.key === Qt.Key_Escape) root.close();
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

        anchors.centerIn: parent
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
                      + "     1–6 tools   Ctrl+Z undo   Ctrl+C / Enter copy   Ctrl+S save   Esc close"
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

            Item {
                id: stage

                anchors.centerIn: parent
                width: Math.round(root.imgW * root.fit)
                height: Math.round(root.imgH * root.fit)
                clip: true

                // Native-size layers, scaled as one. Everything inside is in
                // image pixels, including the MouseArea's coordinates.
                Item {
                    id: layers

                    width: root.imgW
                    height: root.imgH
                    scale: root.fit
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
                            // Not onPainted: that is not emitted for a paint
                            // that drew nothing new, which is the usual export.
                            if (root.pendingExport !== "") Qt.callLater(root.finishExport);
                        }
                    }

                    Canvas {
                        id: live

                        anchors.fill: parent
                        renderTarget: Canvas.FramebufferObject
                        renderStrategy: Canvas.Cooperative

                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            const op = root.draft;
                            if (!op) return;
                            if (op.tool !== "pixelate") {
                                root.drawOp(ctx, op);
                                return;
                            }
                            // A mosaic is drawn for real only on release; the
                            // drag shows the region it will cover.
                            const r = root.norm(op);
                            ctx.fillStyle = "rgba(17,17,27,0.35)";
                            ctx.fillRect(r.x, r.y, r.w, r.h);
                            ctx.strokeStyle = Theme.text;
                            ctx.lineWidth = 1 / root.fit;
                            ctx.strokeRect(r.x, r.y, r.w, r.h);
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: root.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor

                        onPressed: mouse => {
                            root.commitText();
                            const x = mouse.x, y = mouse.y;
                            if (root.tool === "text") {
                                textEditor.text = "";
                                root.textAt = { x: x, y: y };
                                textEditor.forceActiveFocus();
                                return;
                            }
                            root.draft = root.tool === "pen"
                                ? { tool: "pen", color: root.penColor, width: root.strokeWidth,
                                    points: [{ x: x, y: y }] }
                                : { tool: root.tool, color: root.penColor, width: root.strokeWidth,
                                    block: root.blockPx, x1: x, y1: y, x2: x, y2: y };
                            live.requestPaint();
                        }

                        onPositionChanged: mouse => {
                            const op = root.draft;
                            if (!op) return;
                            const x = Math.max(0, Math.min(root.imgW, mouse.x));
                            const y = Math.max(0, Math.min(root.imgH, mouse.y));
                            if (op.tool === "pen") op.points.push({ x: x, y: y });
                            else { op.x2 = x; op.y2 = y; }
                            live.requestPaint();
                        }

                        onReleased: {
                            const op = root.draft;
                            root.draft = null;
                            live.requestPaint();
                            if (!op) return;
                            // A click with a shape tool draws nothing; with the
                            // pen it is a dot, which is what a click means there.
                            if (op.tool !== "pen"
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
                            }
                        }
                    }
                }
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
