pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Qt.labs.folderlistmodel
import QtQuick

// SUPER+W wallpaper picker: a horizontally-scrolling grid of thumbnails driven
// by the arrow keys, in place of the old `rofi -show-icons` grid that
// hypr/scripts/wallpaper-selector.sh used to draw.
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

    // Whole columns only: a partly-visible tile at the right edge reads as a
    // rendering glitch rather than as "there is more this way".
    readonly property int columns: Math.max(2, Math.min(6,
        Math.floor((root.width - 96) / grid.cellWidth)))

    title: "Wallpaper"
    placeholder: "type to filter"
    subtitle: grid.currentIndex >= 0 && grid.currentIndex < root.shown.length
              ? root.shown[grid.currentIndex].name : ""
    countLabel: root.shown.length + " / " + root.wallpapers.length
    footerText: root.shown.length === 0
                ? "No wallpapers match"
                : "← →  move    ↑ ↓  page    ↵  apply    Esc  cancel"
    footerColor: root.shown.length === 0 ? Theme.red : Theme.overlay0

    // 36 = OverlayPanel's padding on both sides, which the body sits inside.
    panelWidth: grid.cellWidth * root.columns + 36
    bodyHeight: grid.cellHeight

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
        case Qt.Key_Left:  grid.moveCurrentIndexLeft();  break;
        case Qt.Key_Right: grid.moveCurrentIndexRight(); break;
        // Up/Down step within a column, so in a one-row grid they are dead
        // keys. Page with them instead, as PageUp/PageDown do.
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

    // Move the cursor somewhere far away -- opening, filtering, Home/End,
    // PageUp/PageDown. Jump, do not scroll: the contentX animation on the grid
    // would otherwise drag the view across every column in between, and each
    // frame of that queues a screenful of thumbnails the loader then has to
    // chew through before it reaches the ones actually on screen. Only the
    // one-column arrow step is worth animating.
    function jumpTo(index: int): void {
        grid.jumping = true;
        grid.currentIndex = Math.max(-1, Math.min(root.shown.length - 1, index));
        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
        grid.jumping = false;
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

    GridView {
        id: grid

        // One row, running off the right edge rather than wrapping: a
        // filmstrip that scrolls sideways under the arrows. FlowTopToBottom
        // with a height of exactly one cell is what fixes it to one row.
        flow: GridView.FlowTopToBottom
        cellWidth: 440
        cellHeight: 256

        anchors.fill: parent

        clip: true
        model: root.shown
        boundsBehavior: Flickable.StopAtBounds
        cacheBuffer: cellWidth * 4
        highlightMoveDuration: 0

        // moveCurrentIndex* already scrolls the view to keep the cursor
        // visible; this only softens the one-column step. Suppressed for a
        // deliberate jump (see selectCurrent) and while dragging.
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

            width: grid.cellWidth
            height: grid.cellHeight

            ClippingRectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: 10
                color: Theme.surface0
                border.width: tile.selected ? 3 : 1
                border.color: tile.selected ? Theme.lavender
                                            : (tile.isCurrent ? Theme.surface2 : Theme.mantle)

                Image {
                    id: thumb

                    anchors.fill: parent
                    source: "file://" + tile.modelData.path
                    fillMode: Image.PreserveAspectCrop
                    // Decode near tile size -- a 4K jpeg scaled down by the
                    // loader, not a 4K pixmap scaled by the scene. 2x so the
                    // crop still has pixels to spare.
                    sourceSize.width: grid.cellWidth * 2
                    sourceSize.height: grid.cellHeight * 2
                    asynchronous: true
                    cache: true
                    smooth: true

                    // 312 wallpapers do not all decode at once; fade each
                    // one in over its placeholder rather than popping.
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                // An image Qt has no decoder for would otherwise sit
                // there as an empty tile, indistinguishable from one still
                // loading. (qt6-imageformats covers webp and avif.)
                Text {
                    anchors.fill: parent
                    anchors.margins: 8
                    visible: thumb.status === Image.Error
                    text: tile.modelData.name
                    color: Theme.overlay0
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                // A dot on the wallpaper that is currently applied.
                Rectangle {
                    anchors { right: parent.right; top: parent.top; margins: 6 }
                    visible: tile.isCurrent
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.green
                }
            }
        }
    }

    // One stationary hover/click surface over the grid rather than a
    // MouseArea per tile. A per-tile one is dragged under the pointer every
    // time the arrow keys scroll the view, and the synthetic hover that
    // produces yanks the cursor straight back off the tile the keyboard
    // just moved to. It is a sibling of the GridView, not a child: a child
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

        function indexUnder(x: real, y: real): int {
            return grid.indexAt(x + grid.contentX, y + grid.contentY);
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

        // Let the wheel reach the GridView underneath.
        onWheel: wheel => wheel.accepted = false
    }
}
