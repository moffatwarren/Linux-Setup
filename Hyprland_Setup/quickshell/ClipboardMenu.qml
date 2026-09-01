pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick

// SUPER+V clipboard history, in place of the `rofi -dmenu` list that
// clipboard-menu.sh used to draw. Same window as the app launcher and the
// wallpaper picker -- see OverlayPanel.qml.
//
// hypr/scripts/clipboard-history.sh is the whole backend: `--list` prints the
// history as JSON (with a cached thumbnail path for each image entry), and
// `--copy`/`--delete` act on one id. Nothing here parses cliphist's output, so
// the placeholder-vs-thumbnail logic lives in one place.
OverlayPanel {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string script: root.home + "/.config/hypr/scripts/clipboard-history.sh"

    // { id, kind: "text"|"image", label, detail, thumb }, newest first.
    property var entries: []

    readonly property var shown: {
        const q = root.filterText.trim().toLowerCase();
        if (q.length === 0) return root.entries;
        return root.entries.filter(e => e.label.toLowerCase().includes(q)
                                     || e.kind.includes(q));
    }

    readonly property var current: list.currentIndex >= 0 && list.currentIndex < root.shown.length
                                  ? root.shown[list.currentIndex] : null

    title: "Clipboard"
    placeholder: "type to filter"
    subtitle: root.current && root.current.kind === "image" ? root.current.detail : ""
    countLabel: root.shown.length + " / " + root.entries.length
    footerText: root.entries.length === 0
                ? "Clipboard history is empty"
                : (root.shown.length === 0
                   ? "Nothing matches"
                   : "↑ ↓  move    ↵  copy    Del  remove    Esc  cancel")
    footerColor: root.shown.length === 0 ? Theme.red : Theme.overlay0

    panelWidth: 720
    bodyHeight: rowHeight * 8

    readonly property int rowHeight: 48

    onOpened: {
        listMouse.lastY = -1;
        root.refresh();
        root.jumpTo(0);
    }

    onAccepted: if (root.current) root.copy(root.current.id)

    onNavKey: event => {
        switch (event.key) {
        case Qt.Key_Up:
            root.jumpTo(list.currentIndex <= 0 ? root.shown.length - 1
                                               : list.currentIndex - 1); break;
        case Qt.Key_Down:
            root.jumpTo(list.currentIndex >= root.shown.length - 1 ? 0
                                                                   : list.currentIndex + 1); break;
        case Qt.Key_PageUp:
            root.jumpTo(list.currentIndex - 8); break;
        case Qt.Key_PageDown:
            root.jumpTo(list.currentIndex + 8); break;
        case Qt.Key_Home:
            root.jumpTo(0); break;
        case Qt.Key_End:
            root.jumpTo(root.shown.length - 1); break;
        // Delete drops the entry and leaves the menu open, so a run of junk
        // can be cleared out without reopening it between each one.
        case Qt.Key_Delete:
            if (root.current) root.remove(root.current.id);
            break;
        default:
            return; // let the filter box have the keystroke
        }
        event.accepted = true;
    }

    onFilterTextChanged: root.jumpTo(0)

    function jumpTo(index: int): void {
        list.currentIndex = Math.max(-1, Math.min(root.shown.length - 1, index));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }

    function refresh(): void {
        if (!listProc.running) listProc.running = true;
    }

    function copy(id: string): void {
        // Close first so the keyboard grab is gone before the paste target
        // gets it back.
        root.close();
        Quickshell.execDetached([root.script, "--copy", id]);
    }

    function remove(id: string): void {
        // Drop it from the model straight away rather than waiting for the
        // reload: the row is gone the instant the key is pressed, and the
        // cursor keeps its place in the shortened list.
        const at = list.currentIndex;
        root.entries = root.entries.filter(e => e.id !== id);
        root.jumpTo(Math.min(at, root.shown.length - 1));

        // execDetached rather than a Process: holding Delete down fires faster
        // than one finishes, and reassigning a running Process's command is not
        // a queue. Each delete is independent, so let them overlap.
        Quickshell.execDetached([root.script, "--delete", id]);
        reconcile.restart();
    }

    Process {
        id: listProc

        command: [root.script, "--list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (Array.isArray(parsed)) root.entries = parsed;
                } catch (e) {
                    // Keep the last good list rather than blanking the menu.
                }
                root.jumpTo(list.currentIndex < 0 ? 0 : list.currentIndex);
            }
        }
    }

    // Reload once the deletes have settled: the optimistic removal above is
    // only the display, and a reload racing an in-flight delete would put the
    // row back for a frame.
    Timer {
        id: reconcile
        interval: 300
        onTriggered: if (root.open) root.refresh()
    }

    ListView {
        id: list

        anchors.fill: parent
        clip: true
        model: root.shown
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        cacheBuffer: root.rowHeight * 12

        delegate: Item {
            id: row

            required property var modelData
            required property int index

            readonly property bool selected: row.index === list.currentIndex
            readonly property bool isImage: row.modelData.kind === "image"

            width: list.width
            height: root.rowHeight

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 2
                anchors.bottomMargin: 2
                radius: 8
                color: row.selected ? Theme.surface0 : "transparent"
                border.width: 1
                border.color: row.selected ? Theme.lavender : "transparent"

                // Image entries get their thumbnail where a text entry gets a
                // glyph, so the two line up in one column.
                ClippingRectangle {
                    id: preview

                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 60
                    height: 34
                    radius: 6
                    color: row.isImage ? Theme.mantle : "transparent"

                    Image {
                        anchors.fill: parent
                        visible: row.isImage && row.modelData.thumb.length > 0
                        source: row.modelData.thumb.length > 0
                                ? "file://" + row.modelData.thumb : ""
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: 120
                        sourceSize.height: 68
                        asynchronous: true
                        cache: true
                        smooth: true
                    }

                    // Written as escapes: nerd font glyphs are private-use
                    // codepoints and pasting them literally yields an empty
                    // string. f0f6 = file-text, f03e = image.
                    Text {
                        anchors.centerIn: parent
                        visible: !row.isImage || row.modelData.thumb.length === 0
                        text: row.isImage ? "\uf03e" : "\uf0f6"
                        color: Theme.overlay0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 4
                    }
                }

                Text {
                    id: label

                    anchors.left: preview.right
                    anchors.leftMargin: 12
                    anchors.right: detail.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.label
                    color: row.selected ? Theme.lavender : Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Text {
                    id: detail

                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.baseline: label.baseline
                    text: row.modelData.detail
                    color: Theme.overlay0
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }
    }

    // One stationary hover surface rather than a MouseArea per row -- see
    // WallpaperPicker for why a per-row one fights the arrow keys.
    // Right-click removes an entry, matching the Delete key.
    MouseArea {
        id: listMouse

        anchors.fill: list
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        property real lastX: -1
        property real lastY: -1

        function indexUnder(x: real, y: real): int {
            return list.indexAt(x + list.contentX, y + list.contentY);
        }

        onPositionChanged: mouse => {
            const first = listMouse.lastY < 0;
            const moved = Math.abs(mouse.x - listMouse.lastX) > 1
                       || Math.abs(mouse.y - listMouse.lastY) > 1;
            listMouse.lastX = mouse.x;
            listMouse.lastY = mouse.y;
            if (first || !moved) return;

            const i = listMouse.indexUnder(mouse.x, mouse.y);
            if (i >= 0) list.currentIndex = i;
        }

        onClicked: mouse => {
            const i = listMouse.indexUnder(mouse.x, mouse.y);
            if (i < 0) return;
            if (mouse.button === Qt.RightButton) root.remove(root.shown[i].id);
            else root.copy(root.shown[i].id);
        }

        // Let the wheel reach the ListView underneath.
        onWheel: wheel => wheel.accepted = false
    }
}
