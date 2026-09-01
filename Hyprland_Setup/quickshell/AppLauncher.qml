pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick

// SUPER+SPACE app launcher, in place of `rofi -show drun`.
//
// Same window as the wallpaper picker and the clipboard history -- see
// OverlayPanel.qml -- so the three menus are one interface rather than three
// programs with three ideas about what a menu looks like.
//
// Applications come from Quickshell's own DesktopEntries scanner, so there is
// no .desktop parsing here and `entry.execute()` honours Exec field codes,
// Terminal=true and the startup working directory.
OverlayPanel {
    id: root

    readonly property string home: Quickshell.env("HOME")

    // How many times each entry has been launched from here, id -> count,
    // persisted so the apps you actually use float to the top of an empty
    // search, the way `rofi -show drun` used to.
    property var usage: ({})

    // The service is lazy: nothing populates `applications` until something
    // binds to it, which this does.
    readonly property var allApps: DesktopEntries.applications.values

    readonly property var apps: root.allApps.filter(e => !e.noDisplay)

    // `apps` narrowed and ranked by the filter box. Rank first (a prefix of
    // the name beats a hit buried in the description), then launch count, then
    // alphabetically -- so an empty query is the most-used apps in order.
    readonly property var shown: {
        const q = root.filterText.trim().toLowerCase();
        const scored = [];
        for (const e of root.apps) {
            const rank = root.score(e, q);
            if (rank < 0) continue;
            scored.push({ entry: e, rank: rank });
        }
        scored.sort((a, b) => {
            if (a.rank !== b.rank) return a.rank - b.rank;
            const ua = root.usage[a.entry.id] ?? 0;
            const ub = root.usage[b.entry.id] ?? 0;
            if (ua !== ub) return ub - ua;
            return String(a.entry.name).localeCompare(String(b.entry.name));
        });
        return scored.map(s => s.entry);
    }

    readonly property var current: list.currentIndex >= 0 && list.currentIndex < root.shown.length
                                  ? root.shown[list.currentIndex] : null

    title: "Apps"
    placeholder: "type to search"
    subtitle: root.current ? (String(root.current.comment).length > 0
                             ? String(root.current.comment)
                             : String(root.current.genericName)) : ""
    countLabel: root.shown.length + " / " + root.apps.length
    footerText: root.shown.length === 0
                ? "No applications match"
                : "↑ ↓  move    ↵  launch    Esc  cancel"
    footerColor: root.shown.length === 0 ? Theme.red : Theme.overlay0

    panelWidth: 720
    bodyHeight: rowHeight * 9

    readonly property int rowHeight: 42

    onOpened: {
        listMouse.lastY = -1;
        root.jumpTo(0);
    }

    onAccepted: if (root.current) root.launch(root.current)

    onNavKey: event => {
        switch (event.key) {
        // Wrap at both ends: with the cursor parked on the last entry, Down is
        // otherwise a dead key rather than the way back to the top.
        case Qt.Key_Up:
            root.jumpTo(list.currentIndex <= 0 ? root.shown.length - 1
                                               : list.currentIndex - 1); break;
        case Qt.Key_Down:
            root.jumpTo(list.currentIndex >= root.shown.length - 1 ? 0
                                                                   : list.currentIndex + 1); break;
        case Qt.Key_PageUp:
            root.jumpTo(list.currentIndex - 9); break;
        case Qt.Key_PageDown:
            root.jumpTo(list.currentIndex + 9); break;
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
    onFilterTextChanged: root.jumpTo(0)

    function jumpTo(index: int): void {
        list.currentIndex = Math.max(-1, Math.min(root.shown.length - 1, index));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
    }

    // Where an entry matches, as a rank: lower sorts first, -1 means no match.
    // Name hits beat metadata hits, and a hit at the start of a word beats one
    // in the middle, so "fi" puts Firefox above "Wi-Fi settings".
    function score(entry, q: string): int {
        if (q.length === 0) return 0;

        const name = String(entry.name ?? "").toLowerCase();
        const at = name.indexOf(q);
        if (at === 0) return 0;
        if (at > 0) return " -_/(".includes(name[at - 1]) ? 1 : 2;

        const generic = String(entry.genericName ?? "").toLowerCase();
        if (generic.includes(q)) return 3;

        const keywords = (entry.keywords ?? []).join(" ").toLowerCase();
        if (keywords.includes(q)) return 4;

        const comment = String(entry.comment ?? "").toLowerCase();
        if (comment.includes(q)) return 5;

        // Last resort: what the entry actually runs, which is how you find an
        // app you only know by its binary name.
        const exec = String(entry.execString ?? "").toLowerCase();
        if (exec.includes(q)) return 6;

        return -1;
    }

    function launch(entry): void {
        const counts = Object.assign({}, root.usage);
        counts[entry.id] = (counts[entry.id] ?? 0) + 1;
        root.usage = counts;
        usageFile.setText(JSON.stringify(counts));

        // Close first, so the overlay has given the keyboard back by the time
        // the new window maps and asks for focus.
        root.close();
        entry.execute();
    }

    FileView {
        id: usageFile

        path: root.home + "/.cache/quickshell-launcher.json"
        preload: true
        // Absent until the first launch; that is not worth an error on every
        // bar startup.
        printErrors: false

        onLoaded: {
            try {
                const parsed = JSON.parse(usageFile.text());
                if (parsed && typeof parsed === "object") root.usage = parsed;
            } catch (e) {
                root.usage = ({});
            }
        }
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

            width: list.width
            height: root.rowHeight

            Rectangle {
                anchors.fill: parent
                anchors.topMargin: 1
                anchors.bottomMargin: 1
                radius: 8
                color: row.selected ? Theme.surface0 : "transparent"
                border.width: 1
                border.color: row.selected ? Theme.lavender : "transparent"

                IconImage {
                    id: icon

                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 26
                    asynchronous: true
                    source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                }

                Text {
                    id: appName

                    anchors.left: icon.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width * 0.45)
                    text: row.modelData.name
                    color: row.selected ? Theme.lavender : Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                }

                Text {
                    anchors.left: appName.right
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.baseline: appName.baseline
                    text: String(row.modelData.genericName ?? "")
                    color: Theme.overlay0
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }
    }

    // One stationary hover surface rather than a MouseArea per row, for the
    // reason spelled out in WallpaperPicker: the arrow keys scroll the view,
    // which drags rows under a motionless pointer, and the synthetic hover
    // that produces drags the selection straight back off the row the keyboard
    // just moved to. A sibling of the ListView, never a child.
    MouseArea {
        id: listMouse

        anchors.fill: list
        hoverEnabled: true
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
            if (i >= 0) root.launch(root.shown[i]);
        }

        // Let the wheel reach the ListView underneath.
        onWheel: wheel => wheel.accepted = false
    }
}
