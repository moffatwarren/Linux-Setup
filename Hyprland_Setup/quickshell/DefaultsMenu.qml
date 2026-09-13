pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick

// SUPER+D default applications manager: which app opens web links, text and
// code, video, images and folders -- the last of which is also what SUPER+E
// opens (hypr/scripts/launch-file-manager.sh).
//
// Same base window as KeybindsHelp.qml, AppLauncher.qml, ClipboardMenu.qml and
// WallpaperPicker.qml -- see OverlayPanel.qml.
//
// This file draws; it does not classify. hypr/scripts/default-apps.sh --list
// decides what belongs in each category, from each .desktop entry's own
// MimeType= key, and prints the candidates and the current default as JSON --
// the system-stats.sh split, where the script produces raw values and the QML
// formats them. That is not a stylistic choice: an earlier version guessed from
// hardcoded application names here and needed a probe list to see swayimg,
// swappy and imv at all, because Quickshell's DesktopEntries.applications masks
// NoDisplay=true entries at the C++ level and those three set it.
OverlayPanel {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/scripts/default-apps.sh"

    // { browser: { default: "firefox.desktop", apps: [{id,name,icon,generic}] }, ... }
    property var data: ({})

    property string selectedCategory: "All"

    readonly property var categories: [
        { id: "browser", name: "Web Browser",  icon: "\uf268", desc: "Web links and HTML documents" },
        { id: "editor",  name: "Text Editor",  icon: "\uf121", desc: "Text and every programming language" },
        { id: "video",   name: "Video Player", icon: "\uf008", desc: "Video media files" },
        { id: "image",   name: "Image Viewer", icon: "\uf03e", desc: "Graphic and image files" },
        // Unlike the four above, a file explorer is not just anything that
        // declares inode/directory -- VSCodium does. default-apps.sh also
        // requires Categories=FileManager; this file only draws the result.
        { id: "filemanager", name: "File Explorer", icon: "\uf07c", desc: "Folders, and what SUPER+E opens" }
    ]

    readonly property var tabs: ["All", "Web Browser", "Text Editor", "Video Player", "Image Viewer", "File Explorer"]

    title: "Default Applications"
    subtitle: "SUPER+D • Browser, Editor, Video, Image & Files"
    placeholder: "type to filter applications"
    footerText: "Click an app to set it as default    ← →  category    ↑ ↓  scroll    Esc  close"
    footerColor: Theme.overlay0
    countLabel: root.visibleCount + (root.visibleCount === 1 ? " app" : " apps")

    panelWidth: 840
    bodyHeight: 480

    readonly property int visibleCount: {
        let n = 0;
        for (let i = 0; i < root.categories.length; i++) {
            const c = root.categories[i];
            if (root.selectedCategory === "All" || root.selectedCategory === c.name)
                n += root.appsFor(c.id).length;
        }
        return n;
    }

    function defaultId(catId: string): string {
        return String(root.data?.[catId]?.default ?? "");
    }

    function defaultName(catId: string): string {
        const id = root.defaultId(catId);
        if (!id) return "";
        const all = root.data?.[catId]?.apps ?? [];
        const hit = all.find(a => a.id === id);
        // A default set to something not in the candidate list is still the
        // default -- name it by its id rather than claiming none is set.
        return hit ? hit.name : id.replace(/\.desktop$/, "");
    }

    // The script has already sorted: current default first, then apps whose
    // Categories match the role, then alphabetically. Only the filter is ours.
    function appsFor(catId: string): var {
        const all = root.data?.[catId]?.apps ?? [];
        const q = root.filterText.trim().toLowerCase();
        if (!q) return all;
        return all.filter(a =>
            String(a.name ?? "").toLowerCase().includes(q)
            || String(a.generic ?? "").toLowerCase().includes(q)
            || String(a.id ?? "").toLowerCase().includes(q));
    }

    function refresh(): void {
        if (!listProc.running) listProc.running = true;
    }

    // One set at a time, last request wins while one is in flight -- clicking
    // two rows quickly must not leave two python writes racing for the same
    // mimeapps.list.
    property var queuedSet: null

    function setDefault(catId: string, app: var): void {
        // Optimistic, so the badge moves on the click rather than on the
        // process exiting; --list reconciles it a moment later.
        const next = Object.assign({}, root.data);
        next[catId] = Object.assign({}, next[catId] ?? {}, { "default": app.id });
        root.data = next;

        const req = [catId, app.id, String(app.name ?? app.id)];
        if (setProc.running) root.queuedSet = req;
        else root.runSet(req);
    }

    function runSet(req: var): void {
        setProc.command = ["bash", root.script, "--set", req[0], req[1], req[2]];
        setProc.running = true;
    }

    Process {
        id: listProc
        command: ["bash", root.script, "--list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text);
                    if (parsed && typeof parsed === "object") root.data = parsed;
                } catch (e) {
                    // Keep the last good answer rather than blanking the menu.
                }
            }
        }
    }

    Process {
        id: setProc
        onExited: {
            if (root.queuedSet) {
                const req = root.queuedSet;
                root.queuedSet = null;
                root.runSet(req);
            } else {
                root.refresh();
            }
        }
    }

    onOpened: {
        root.selectedCategory = "All";
        root.refresh();
        flick.contentY = 0;
    }

    onAccepted: root.close()

    onNavKey: event => {
        let i = root.tabs.indexOf(root.selectedCategory);
        if (i < 0) i = 0;
        const maxY = Math.max(0, flick.contentHeight - flick.height);

        switch (event.key) {
        case Qt.Key_Left:
            root.selectedCategory = root.tabs[i <= 0 ? root.tabs.length - 1 : i - 1];
            flick.contentY = 0;
            break;
        case Qt.Key_Right:
            root.selectedCategory = root.tabs[i >= root.tabs.length - 1 ? 0 : i + 1];
            flick.contentY = 0;
            break;
        case Qt.Key_Up:       flick.contentY = Math.max(0, flick.contentY - 80); break;
        case Qt.Key_Down:     flick.contentY = Math.min(maxY, flick.contentY + 80); break;
        case Qt.Key_PageUp:   flick.contentY = Math.max(0, flick.contentY - 240); break;
        case Qt.Key_PageDown: flick.contentY = Math.min(maxY, flick.contentY + 240); break;
        case Qt.Key_Home:     flick.contentY = 0; break;
        case Qt.Key_End:      flick.contentY = maxY; break;
        default:
            return;   // anything else types into the filter box
        }
        event.accepted = true;
    }

    // Category filter pills. Safe to give these their own MouseAreas: they sit
    // in a static Row, not inside the flickable (the hover-selection trap).
    Row {
        id: categoryRow
        anchors.top: parent.top
        anchors.left: parent.left
        spacing: 6

        Repeater {
            model: root.tabs

            Rectangle {
                id: pillRect
                required property string modelData

                readonly property bool isSelected: root.selectedCategory === pillRect.modelData
                readonly property string labelText: ({
                    "Web Browser": "Browser", "Text Editor": "Editor",
                    "Video Player": "Video",  "Image Viewer": "Image",
                    "File Explorer": "Files"
                })[pillRect.modelData] ?? pillRect.modelData

                implicitWidth: catText.implicitWidth + 16
                implicitHeight: 24
                radius: 6
                color: pillRect.isSelected ? Theme.blue
                                           : (catMouse.containsMouse ? Theme.surface0 : Theme.surface1)

                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    id: catText
                    anchors.centerIn: parent
                    text: pillRect.labelText
                    color: pillRect.isSelected ? Theme.crust : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    font.bold: pillRect.isSelected
                }

                MouseArea {
                    id: catMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.selectedCategory = pillRect.modelData;
                        flick.contentY = 0;
                    }
                }
            }
        }
    }

    Flickable {
        id: flick

        anchors {
            top: categoryRow.bottom
            topMargin: 12
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        clip: true
        contentWidth: width
        contentHeight: contentCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: contentCol
            width: flick.width
            spacing: 16

            Repeater {
                model: root.categories

                delegate: Column {
                    id: sec
                    required property var modelData

                    readonly property var catApps: root.appsFor(sec.modelData.id)
                    readonly property string defId: root.defaultId(sec.modelData.id)
                    readonly property string defName: root.defaultName(sec.modelData.id)

                    visible: root.selectedCategory === "All"
                             || root.selectedCategory === sec.modelData.name
                    width: contentCol.width
                    spacing: 8

                    Item {
                        width: parent.width
                        height: 32

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: sec.modelData.icon
                                color: Theme.mauve
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 1
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: sec.modelData.name
                                color: Theme.mauve
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize + 1
                                font.bold: true
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "• " + sec.modelData.desc
                                color: Theme.overlay0
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: defRow.implicitWidth + 14
                            height: 24
                            radius: 6
                            color: Theme.surface0
                            border.width: 1
                            border.color: sec.defName ? Theme.green : Theme.surface2

                            Row {
                                id: defRow
                                anchors.centerIn: parent
                                spacing: 6

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: sec.defName ? ("Default: " + sec.defName) : "No default set"
                                    color: sec.defName ? Theme.green : Theme.overlay0
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 2
                                    font.bold: sec.defName.length > 0
                                }
                            }
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 1
                            color: Theme.surface1
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 2
                        spacing: 8
                        visible: sec.catApps.length > 0

                        Repeater {
                            model: sec.catApps

                            delegate: Rectangle {
                                id: card
                                required property var modelData

                                readonly property bool isDefault: card.modelData.id === sec.defId

                                width: Math.floor((parent.width - 8) / 2)
                                height: 48
                                radius: 8
                                color: card.isDefault ? Theme.surface1
                                                      : (cardMouse.containsMouse ? Theme.surface0 : Theme.base)
                                border.width: 1
                                border.color: card.isDefault ? Theme.green
                                                             : (cardMouse.containsMouse ? Theme.lavender : Theme.surface1)

                                Behavior on color { ColorAnimation { duration: 100 } }
                                Behavior on border.color { ColorAnimation { duration: 100 } }

                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.right: statusCol.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10

                                    IconImage {
                                        anchors.verticalCenter: parent.verticalCenter
                                        implicitSize: 26
                                        asynchronous: true
                                        source: Quickshell.iconPath(String(card.modelData.icon ?? ""),
                                                                    "application-x-executable")
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 36
                                        spacing: 2

                                        Text {
                                            width: parent.width
                                            text: card.modelData.name
                                            color: card.isDefault ? Theme.lavender : Theme.text
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: parent.width
                                            text: String(card.modelData.generic || card.modelData.id)
                                            color: Theme.overlay0
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                Item {
                                    id: statusCol
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: statusBadge.implicitWidth
                                    height: 24

                                    Rectangle {
                                        id: statusBadge
                                        anchors.centerIn: parent
                                        implicitWidth: statusText.implicitWidth + 12
                                        height: 22
                                        radius: 6
                                        color: card.isDefault ? Theme.green
                                                              : (cardMouse.containsMouse ? Theme.blue : "transparent")
                                        border.width: card.isDefault || cardMouse.containsMouse ? 0 : 1
                                        border.color: Theme.surface2

                                        Text {
                                            id: statusText
                                            anchors.centerIn: parent
                                            text: card.isDefault ? "✓ Default" : "Set Default"
                                            color: card.isDefault || cardMouse.containsMouse ? Theme.crust : Theme.subtext0
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 2
                                            font.bold: card.isDefault || cardMouse.containsMouse
                                        }
                                    }
                                }

                                MouseArea {
                                    id: cardMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.setDefault(sec.modelData.id, card.modelData)
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 36
                        visible: sec.catApps.length === 0

                        Text {
                            anchors.centerIn: parent
                            text: root.filterText.length > 0
                                  ? "No applications match the filter"
                                  : "No application declares it can open these files"
                            color: Theme.overlay0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            font.italic: true
                        }
                    }
                }
            }
        }
    }
}
