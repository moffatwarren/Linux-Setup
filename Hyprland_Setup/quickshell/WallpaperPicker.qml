pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Qt.labs.folderlistmodel
import QtQuick
import QtQuick.Shapes

// SUPER+W wallpaper picker: a horizontally-scrolling strip of slanted
// thumbnails driven by the arrow keys, in place of the old `rofi -show-icons`
// grid that hypr/scripts/wallpaper-selector.sh used to draw.
//
// The window, the header, the filter box and the footer are OverlayPanel's --
// shared with the app launcher and the clipboard history, so all three are
// visibly the same menu. Only the body below is specific to wallpapers.
//
// It lives inside the bar process rather than in a `qs -p` of its own, so
// opening it costs nothing and the decoded thumbnails stay in Qt's pixmap
// cache between openings. shell.qml holds it in a LazyLoader and owns the
// IpcHandler the keybind pokes: `qs ipc call wallpaper toggle`.
OverlayPanel {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string wallpaperDir: root.home + "/Pictures/wallpapers"

    // Every image in the directory, name-sorted, as { name, path }.
    property var wallpapers: []
    // What the grid actually shows: `wallpapers` narrowed by the filter box.
    readonly property var shown: {
        const q = root.filterText.trim().toLowerCase();
        if (q.length === 0) return root.wallpapers;
        return root.wallpapers.filter(w => w.name.toLowerCase().includes(q));
    }

    // The wallpaper in use, read out of hyprlock.conf rather than by shelling
    // out to `awww query` -- wallpaper-set.sh writes both, and a FileView costs
    // no process. Used to land the cursor on the current wallpaper on open.
    readonly property string currentPath: {
        const m = /^[ \t]*path = (.+)$/m.exec(hyprlockConf.text());
        return m ? m[1].trim() : "";
    }

    // Tile geometry. Every tile is the same parallelogram: a tileWidth x
    // tileHeight box with its top edge pushed tileSkew to the right. Tiles
    // nest slope against slope, so one tile further along is tilePitch.
    readonly property int tileWidth: 250
    readonly property int tileHeight: 360
    readonly property int tileSkew: 80
    readonly property int tileGap: 8
    readonly property int tilePitch: root.tileWidth - root.tileSkew + root.tileGap
    // The selected tile is tileGrow wider than the rest and stands tileRise
    // proud of the strip at both top and bottom, its sloping sides extended
    // along the same line so it still nests against its neighbours.
    readonly property int tileGrow: 260
    readonly property int tileRise: 20
    readonly property int growDuration: 170
    // Room for the selected tile's outline, which straddles its edge, inside
    // the strip's clip: the extra height above and below every tile, and the
    // extra width either side of the selected one.
    readonly property int tileEdge: 2
    // How far the selected tile's extended slopes reach past its slot each
    // side at full size, plus its outline. The slot is padded by this much so
    // nothing of it hangs past the strip's clip at either end.
    readonly property real tilePad: root.tileSkew * root.tileRise / root.tileHeight + root.tileEdge

    // Whole tiles only: a partly-visible tile at the right edge reads as a
    // rendering glitch rather than as "there is more this way". The strip is
    // as wide as the screen allows, less a margin and OverlayPanel's padding.
    readonly property int columns: Math.max(2,
        Math.floor((root.width - 132 - root.tileWidth - root.tileGrow) / root.tilePitch) + 1)

    title: "Wallpaper"
    placeholder: "type to filter"
    subtitle: grid.currentIndex >= 0 && grid.currentIndex < root.shown.length
              ? root.shown[grid.currentIndex].name : ""
    countLabel: root.shown.length + " / " + root.wallpapers.length
    footerText: root.shown.length === 0
                ? "No wallpapers match"
                : "← →  wheel  move    ↑ ↓  page    ↵  apply    Esc  cancel"
    footerColor: root.shown.length === 0 ? Theme.red : Theme.overlay0

    // 36 = OverlayPanel's padding on both sides, which the body sits inside.
    panelWidth: Math.ceil((root.columns - 1) * root.tilePitch + root.tileWidth
                          + root.tileGrow + 2 * root.tilePad) + 36
    bodyHeight: root.tileHeight + (root.tileRise + root.tileEdge) * 2

    onOpened: {
        gridMouse.lastX = -1;
        root.selectCurrent();
    }

    onAccepted: {
        if (grid.currentIndex >= 0 && grid.currentIndex < root.shown.length)
            root.apply(root.shown[grid.currentIndex].path);
    }

    onNavKey: event => {
        switch (event.key) {
        case Qt.Key_Left:  root.step(-1); break;
        case Qt.Key_Right: root.step(1);  break;
        // There is only one row, so Up/Down would be dead keys. Page with
        // them instead, as PageUp/PageDown do.
        case Qt.Key_Up:
        case Qt.Key_PageUp:
            root.jumpTo(grid.currentIndex - root.columns); break;
        case Qt.Key_Down:
        case Qt.Key_PageDown:
            root.jumpTo(grid.currentIndex + root.columns); break;
        case Qt.Key_Home:
            root.jumpTo(0); break;
        case Qt.Key_End:
            root.jumpTo(root.shown.length - 1); break;
        default:
            return; // let the filter box have the keystroke
        }
        event.accepted = true;
    }

    // Narrowing the list invalidates the old cursor position.
    onFilterTextChanged: root.jumpTo(root.shown.length > 0 ? 0 : -1)

    // One tile along, animated. Clamped rather than wrapping, so holding an
    // arrow stops at the end of the strip instead of flying back to the start.
    function step(delta: int): void {
        const i = Math.max(0, Math.min(root.shown.length - 1, grid.currentIndex + delta));
        if (i === grid.currentIndex) return;
        grid.currentIndex = i;
        root.reveal(true);
    }

    // Keep the selected tile in view. Done twice, because the tile is still
    // its old width when the cursor lands on it: once now, so a tile that was
    // off the edge comes on screen at all, and again once it has finished
    // widening, so the extra width does not hang off the right-hand side.
    function reveal(animate: bool): void {
        grid.jumping = !animate;
        grid.positionViewAtIndex(grid.currentIndex, ListView.Contain);
        grid.jumping = false;
        revealAgain.animate = animate;
        revealAgain.restart();
    }

    Timer {
        id: revealAgain
        property bool animate: true
        interval: root.growDuration + 20
        onTriggered: {
            if (grid.currentIndex < 0) return;
            grid.jumping = !revealAgain.animate;
            grid.positionViewAtIndex(grid.currentIndex, ListView.Contain);
            grid.jumping = false;
        }
    }

    // Move the cursor somewhere far away -- opening, filtering, Home/End,
    // PageUp/PageDown. Jump, do not scroll: the contentX animation on the grid
    // would otherwise drag the view across every column in between, and each
    // frame of that queues a screenful of thumbnails the loader then has to
    // chew through before it reaches the ones actually on screen. Only the
    // one-column arrow step is worth animating.
    function jumpTo(index: int): void {
        grid.currentIndex = Math.max(-1, Math.min(root.shown.length - 1, index));
        root.reveal(false);
    }

    // Put the cursor on the wallpaper that is already applied, falling back to
    // the first tile when it is not in the directory any more.
    function selectCurrent(): void {
        const i = root.shown.findIndex(w => w.path === root.currentPath);
        root.jumpTo(i >= 0 ? i : 0);
    }

    function apply(path: string): void {
        // No shell in between, so a filename with spaces or quotes needs no
        // escaping on the way to the script.
        Quickshell.execDetached([root.home + "/.config/hypr/scripts/wallpaper-set.sh", path]);
        root.close();
    }

    FileView {
        id: hyprlockConf
        path: root.home + "/.config/hypr/hyprlock.conf"
        watchChanges: true
        onFileChanged: reload()
    }

    FolderListModel {
        id: folder
        folder: "file://" + root.wallpaperDir
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.webp", "*.bmp"]
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
        caseSensitive: false

        // The model populates asynchronously, so rebuild on both signals: the
        // count climbs while it scans and status only settles at the end.
        onStatusChanged: if (status === FolderListModel.Ready) root.rebuild()
        onCountChanged: root.rebuild()
    }

    function rebuild(): void {
        const out = [];
        for (let i = 0; i < folder.count; i++) {
            const name = String(folder.get(i, "fileName"));
            out.push({ name: name, path: root.wallpaperDir + "/" + name });
        }
        root.wallpapers = out;
    }

    ListView {
        id: grid

        // One row of slanted tiles, running off the right edge: a filmstrip
        // that scrolls sideways under the arrows. Each tile is a parallelogram
        // whose sloping sides run parallel to its neighbours', so the strip
        // interlocks -- the spacing is negative by the skew, and what is left
        // is `tileGap` measured horizontally between two sloping edges.
        orientation: ListView.Horizontal
        spacing: root.tileGap - root.tileSkew

        anchors.fill: parent

        clip: true
        model: root.shown
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: root.tilePitch * 6
        highlightFollowsCurrentItem: false

        // Only the one-tile arrow step is animated; suppressed for a
        // deliberate jump (see jumpTo) and while dragging.
        property bool jumping: false

        Behavior on contentX {
            enabled: !grid.dragging && !grid.jumping
            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: tile

            required property var modelData
            required property int index

            readonly property bool selected: tile.index === grid.currentIndex
            readonly property bool isCurrent: tile.modelData.path === root.currentPath

            // 0 → 1 as the tile becomes the selected one. Everything about
            // the wider, taller shape is scaled by it, so it animates as one.
            property real grow: tile.selected ? 1 : 0
            Behavior on grow { NumberAnimation { duration: root.growDuration; easing.type: Easing.OutCubic } }

            // The slope, as horizontal shift per pixel of height.
            readonly property real slope: root.tileSkew / root.tileHeight
            readonly property real rise: root.tileRise * tile.grow

            // The layout slot is wide enough for the whole drawn shape, so
            // the ListView moves the neighbours aside as it widens -- which
            // also leaves the selected tile a few pixels more gap either side
            // than the rest have. The rise goes into the tileRise margin
            // above and below the strip that nothing else occupies.
            width: root.tileWidth + (root.tileGrow + 2 * root.tilePad) * tile.grow
            height: root.tileHeight + (root.tileRise + root.tileEdge) * 2
            // The outline straddles the sloping edge, so the selected tile is
            // drawn over its neighbours rather than under the next one.
            z: tile.selected ? 1 : 0

            opacity: 0.72 + 0.28 * tile.grow

            // The drawn shape's bounding box. Extending a sloping side by
            // `rise` at each end moves it `slope * rise` sideways, so the box
            // is that much wider each side as well as `rise` taller each way;
            // it sits inside the padded slot with the outline's room spare.
            readonly property real boxX: root.tileEdge * tile.grow
            readonly property real boxY: root.tileRise + root.tileEdge - tile.rise
            readonly property real boxW: tile.width - 2 * root.tileEdge * tile.grow
            readonly property real boxH: root.tileHeight + 2 * tile.rise

            // The thumbnail, cropped to the shape's bounding box and rendered
            // into a layer -- a texture of exactly the cropped picture, which
            // the Shape below then cuts to a parallelogram. An Image is a
            // texture provider by itself, but its texture is the whole decoded
            // file: PreserveAspectCrop happens in the scene graph, after. It
            // shares the Shape's geometry exactly, so the texture lands on it
            // one to one.
            Item {
                id: picture

                x: tile.boxX
                y: tile.boxY
                width: tile.boxW
                height: tile.boxH
                visible: false
                layer.enabled: true
                layer.smooth: true

                Image {
                    id: thumb

                    anchors.fill: parent
                    source: "file://" + tile.modelData.path
                    fillMode: Image.PreserveAspectCrop
                    // Decode near tile size -- a 4K jpeg scaled down by the
                    // loader, not a 4K pixmap scaled by the scene. Fixed, not
                    // bound to the animated size, or every frame of the
                    // widening would decode the file again.
                    sourceSize.width: root.tileWidth * 2
                    sourceSize.height: root.tileHeight * 2
                    asynchronous: true
                    cache: true
                    smooth: true
                }
            }

            Shape {
                x: tile.boxX
                y: tile.boxY
                width: tile.boxW
                height: tile.boxH
                // Antialiased slopes; the default renderer leaves them jagged.
                preferredRendererType: Shape.CurveRenderer

                // A placeholder while the thumbnail decodes, so a tile still
                // loading is a dim slab rather than a hole in the strip.
                SkewPath {
                    w: tile.boxW; h: tile.boxH; skew: tile.slope * tile.boxH
                    fillColor: Theme.surface0
                    strokeColor: "transparent"
                }

                SkewPath {
                    w: tile.boxW; h: tile.boxH; skew: tile.slope * tile.boxH
                    fillItem: thumb.status === Image.Ready ? picture : null
                    fillColor: "transparent"
                    strokeColor: "transparent"
                }

                SkewPath {
                    w: tile.boxW; h: tile.boxH; skew: tile.slope * tile.boxH
                    fillColor: "transparent"
                    strokeColor: tile.selected ? Theme.peach : "transparent"
                    strokeWidth: 3
                    joinStyle: ShapePath.MiterJoin
                }
            }

            // An image Qt has no decoder for would otherwise sit there as an
            // empty tile, indistinguishable from one still loading.
            // (qt6-imageformats covers webp and avif.)
            Text {
                anchors.centerIn: parent
                width: tile.width - root.tileSkew * 2
                visible: thumb.status === Image.Error
                text: tile.modelData.name
                color: Theme.overlay0
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 4
                horizontalAlignment: Text.AlignHCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }

            // A dot on the wallpaper that is currently applied, tucked into
            // the top-right corner -- which, on a tile leaning right, is the
            // one corner with room inside the slope.
            Rectangle {
                x: tile.boxX + tile.boxW - 22
                y: tile.boxY + 10
                visible: tile.isCurrent
                width: 8
                height: 8
                radius: 4
                color: Theme.green
            }
        }
    }

    // The parallelogram every tile is drawn with: a w x h box with its top
    // edge pushed `skew` to the right, so the tiles lean like the strip in a
    // film gate.
    component SkewPath: ShapePath {
        property real w
        property real h
        property real skew

        startX: skew
        startY: 0
        PathLine { x: w; y: 0 }
        PathLine { x: w - skew; y: h }
        PathLine { x: 0; y: h }
        PathLine { x: skew; y: 0 }
    }

    // One stationary hover/click surface over the grid rather than a
    // MouseArea per tile. A per-tile one is dragged under the pointer every
    // time the arrow keys scroll the view, and the synthetic hover that
    // produces yanks the cursor straight back off the tile the keyboard
    // just moved to. It is a sibling of the ListView, not a child: a child
    // would go into the flickable's content item and scroll with it.
    MouseArea {
        id: gridMouse

        anchors.fill: grid
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        // Mapping the window in swallows one motion event for wherever the
        // pointer already happened to be, which would otherwise throw away
        // the landing on the current wallpaper before it is even seen.
        // Reset by onOpened; hover takes over on the first genuine move.
        property real lastX: -1
        property real lastY: -1

        // Not grid.indexAt on the pointer: neighbouring tiles' bounding boxes
        // overlap by the skew, so a box test picks the wrong tile in every
        // sloping strip. Undo the slope at this height first -- an unselected
        // tile's left edge is item.x + slope * (tileRise + tileEdge +
        // tileHeight - y), and the selected tile's runs along the same line
        // shifted a few pixels right by its padding -- and the tiles become
        // side-by-side intervals of [x, next.x), each owning the gap after it.
        // indexAt can still land on the left one of two overlapping boxes,
        // so the next tile gets the point if it starts at or before it.
        function indexUnder(x: real, y: real): int {
            const u = x + grid.contentX - root.tileSkew
                      * (root.tileRise + root.tileEdge + root.tileHeight - y) / root.tileHeight;
            let i = grid.indexAt(u, grid.contentY + grid.height / 2);
            if (i < 0) return -1;
            const next = grid.itemAtIndex(i + 1);
            if (next && u >= next.x) i++;
            return i;
        }

        onPositionChanged: mouse => {
            const first = gridMouse.lastX < 0;
            const moved = Math.abs(mouse.x - gridMouse.lastX) > 1
                       || Math.abs(mouse.y - gridMouse.lastY) > 1;
            gridMouse.lastX = mouse.x;
            gridMouse.lastY = mouse.y;
            if (first || !moved) return;

            const i = gridMouse.indexUnder(mouse.x, mouse.y);
            if (i >= 0) grid.currentIndex = i;
        }

        onClicked: mouse => {
            const i = gridMouse.indexUnder(mouse.x, mouse.y);
            if (i >= 0) root.apply(root.shown[i].path);
        }

        // The wheel moves the selection a tile per notch rather than
        // scrolling the strip: a strip scrolled out from under the selection
        // would leave the wide tile somewhere off screen. Down and right are
        // forward. Accumulated, so a touchpad's stream of small deltas steps
        // once per notch's worth rather than once per event.
        property real wheelAccum: 0

        onWheel: wheel => {
            const d = wheel.angleDelta.y !== 0 ? -wheel.angleDelta.y : wheel.angleDelta.x;
            if ((d > 0) !== (gridMouse.wheelAccum > 0)) gridMouse.wheelAccum = 0;
            gridMouse.wheelAccum += d;
            while (Math.abs(gridMouse.wheelAccum) >= 120) {
                const dir = gridMouse.wheelAccum > 0 ? 1 : -1;
                root.step(dir);
                gridMouse.wheelAccum -= dir * 120;
            }
        }
    }
}
