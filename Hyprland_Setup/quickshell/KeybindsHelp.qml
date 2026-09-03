pragma ComponentBehavior: Bound

import QtQuick

// SUPER+K keybind reference. Same window as the app launcher, the clipboard
// history and the wallpaper picker -- see OverlayPanel.qml -- so it is the
// fourth member of that family rather than a fifth idea about what a menu
// looks like.
//
// The list below is HAND-WRITTEN and must be kept in step with
// hypr/modules/binds.lua. It deliberately is not generated from
// `hyprctl binds -j`: that reports the dispatcher and its argument
// (`exec, ~/.config/hypr/scripts/audio-output-toggle.sh`), which is what the
// bind *does*, not what it is *for* -- and "what it is for" is the entire
// reason to open this panel. There is nowhere in Hyprland's bind syntax to
// hang a human description, and the Lua wrapper adds none, so the prose has to
// live somewhere; it lives here.
//
// Unlike the other three overlays there is nothing to activate, so there is no
// selected row and no per-row mouse handling. The arrow keys scroll the view
// directly and Enter just closes -- the filter box is the fast path.
OverlayPanel {
    id: root

    // One entry per section, in the order they are shown. `keys` is split on
    // "+" into keycaps, so a compound key ("1 - 0", "Left-drag") is one token.
    readonly property var groups: [
        {
            name: "Launchers & overlays",
            binds: [
                { keys: "SUPER + SPACE",     desc: "App launcher" },
                { keys: "SUPER + V",         desc: "Clipboard history" },
                { keys: "SUPER + W",         desc: "Wallpaper picker" },
                { keys: "SUPER + SHIFT + W", desc: "Set a random wallpaper" },
                { keys: "SUPER + N",         desc: "Notification centre" },
                { keys: "SUPER + SHIFT + N", desc: "Toggle do-not-disturb" },
                { keys: "SUPER + K",         desc: "This keybind list" },
            ]
        },
        {
            name: "Applications",
            binds: [
                { keys: "SUPER + RETURN", desc: "Terminal" },
                { keys: "SUPER + E",      desc: "File manager" },
                { keys: "SUPER + B",      desc: "Web browser" },
                { keys: "SUPER + T",      desc: "btop, floating system monitor" },
                { keys: "SUPER + G",      desc: "Gemini, in an app window" },
            ]
        },
        {
            name: "Windows",
            binds: [
                { keys: "SUPER + Q",                 desc: "Close the focused window" },
                { keys: "SUPER + F",                 desc: "Maximise" },
                { keys: "SUPER + SHIFT + F",         desc: "Fullscreen" },
                { keys: "SUPER + ALT + F",           desc: "Toggle floating" },
                { keys: "SUPER + J",                 desc: "Toggle the split direction (dwindle)" },
                { keys: "SUPER + ← ↓ ↑ →",           desc: "Move focus" },
                { keys: "SUPER + Left-drag",         desc: "Move the window" },
                { keys: "SUPER + Right-drag",        desc: "Resize the window" },
                { keys: "SUPER + SHIFT + Left-click", desc: "Send the window to the next monitor" },
            ]
        },
        {
            name: "Workspaces",
            binds: [
                { keys: "SUPER + 1 - 0",         desc: "Switch to workspace 1-10" },
                { keys: "SUPER + SHIFT + 1 - 0", desc: "Move the window to workspace 1-10" },
                { keys: "SUPER + Scroll",        desc: "Previous / next workspace" },
            ]
        },
        {
            name: "Screen",
            binds: [
                { keys: "SUPER + S",         desc: "Screenshot a region, annotate in swappy" },
                { keys: "SUPER + ALT + S",   desc: "OCR a region to the clipboard" },
                { keys: "SUPER + CTRL + S",  desc: "Start / stop a screen recording" },
                { keys: "SUPER + SHIFT + Z", desc: "Turn the monitor off / on" },
            ]
        },
        {
            name: "Session",
            binds: [
                { keys: "SUPER + L",         desc: "Lock the screen" },
                { keys: "SUPER + SHIFT + L", desc: "Lock, then suspend" },
                { keys: "SUPER + O",         desc: "Next audio output, of the ones switched on" },
            ]
        },
        {
            name: "Media keys",
            binds: [
                { keys: "Vol Up / Down",        desc: "Volume, 1% a step, with an OSD" },
                { keys: "Mute",                 desc: "Mute the output" },
                { keys: "Brightness Up / Down", desc: "Screen backlight" },
                { keys: "Play / Pause",         desc: "Play or pause the current player" },
                { keys: "Prev / Next",          desc: "Previous / next track" },
            ]
        },
    ]



    readonly property int bindCount: {
        let n = 0;
        for (const g of root.groups) n += g.binds.length;
        return n;
    }

    // `groups` narrowed by the filter box, sections that lose every bind
    // dropped -- so the panel never shows a heading over nothing. Each kept
    // section carries the height it will occupy, which is what the column
    // split below balances on.
    readonly property var shown: {
        const q = root.filterText.trim().toLowerCase();
        const out = [];
        for (const g of root.groups) {
            const hits = q.length === 0 ? g.binds : g.binds.filter(
                b => b.keys.toLowerCase().includes(q)
                  || b.desc.toLowerCase().includes(q)
                  || g.name.toLowerCase().includes(q));
            if (hits.length === 0) continue;
            out.push({ name: g.name, binds: hits,
                       height: root.sectionHeight + hits.length * root.rowHeight });
        }
        return out;
    }

    readonly property int shownCount: {
        let n = 0;
        for (const g of root.shown) n += g.binds.length;
        return n;
    }

    // How many of `shown` go in the left column. Whole sections only: splitting
    // one across the gutter would put a heading at the foot of one column and
    // its binds at the head of the other. Sections are taken in order while
    // moving the next one across still brings the two columns closer together,
    // which for this table lands three on the left and four on the right.
    readonly property int splitAt: {
        let total = 0;
        for (const g of root.shown) total += g.height;
        let used = 0;
        let i = 0;
        for (; i < root.shown.length; i++) {
            const h = root.shown[i].height;
            if (Math.abs((used + h) - (total - used - h)) >= Math.abs(used - (total - used))) break;
            used += h;
        }
        // Never leave the left column empty: a single section is the whole table.
        return Math.max(1, i);
    }

    readonly property var leftGroups: root.shown.slice(0, root.splitAt)
    readonly property var rightGroups: root.shown.slice(root.splitAt)

    title: "Keybinds"
    placeholder: "type to filter"
    countLabel: root.shownCount + " / " + root.bindCount
    footerText: root.shownCount === 0 ? "No keybinds match" : "Esc  close"
    footerColor: root.shownCount === 0 ? Theme.red : Theme.overlay0

    // Two columns, sized so the whole table is on screen at once -- this is a
    // reference, and a cheat sheet you have to scroll blind through is a worse
    // one than the wiki page it replaces. The panel shrinks with the filter
    // rather than leaving a field of empty card below three matching rows.
    readonly property int columnWidth: 520
    readonly property int gutter: 24
    panelWidth: columnWidth * 2 + gutter + 36 // 36 = OverlayPanel's two paddings
    bodyHeight: Math.max(120, Math.max(left.implicitHeight, right.implicitHeight))

    readonly property int rowHeight: 26
    readonly property int sectionHeight: 34
    // The keycap column. Fixed rather than sized to the widest chip run, so
    // every description starts at the same x whatever the filter leaves behind.
    readonly property int keyColumn: 225

    // Nothing here to activate -- Enter is just a second Escape, and no key
    // needs intercepting, so everything else falls through to the filter box.
    onAccepted: root.close()

    // One section: the heading with a rule running out to the column edge,
    // then its binds.
    component Section: Column {
        id: section

        required property var modelData

        width: root.columnWidth

        Item {
            width: parent.width
            height: root.sectionHeight

            Text {
                id: heading

                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                text: section.modelData.name
                color: Theme.mauve
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Rectangle {
                anchors.left: heading.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.verticalCenter: heading.verticalCenter
                height: 1
                color: Theme.surface1
            }
        }

        Repeater {
            model: section.modelData.binds

            delegate: Item {
                id: bindRow

                required property var modelData

                width: root.columnWidth
                height: root.rowHeight

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Repeater {
                        model: bindRow.modelData.keys.split("+").map(k => k.trim())

                        delegate: Row {
                            id: cap

                            required property string modelData
                            required property int index

                            spacing: 5

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: cap.index > 0
                                text: "+"
                                color: Theme.overlay0
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                            }

                            Rectangle {
                                width: capText.implicitWidth + 12
                                height: 19
                                radius: 5
                                color: Theme.surface0
                                border.width: 1
                                border.color: Theme.surface1

                                Text {
                                    id: capText
                                    anchors.centerIn: parent
                                    text: cap.modelData
                                    color: Theme.subtext1
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: root.keyColumn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: bindRow.modelData.desc
                    color: Theme.text
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }

    Column {
        id: left

        anchors.left: parent.left
        anchors.top: parent.top
        width: root.columnWidth

        Repeater {
            model: root.leftGroups
            delegate: Section {}
        }
    }

    Column {
        id: right

        anchors.right: parent.right
        anchors.top: parent.top
        width: root.columnWidth

        Repeater {
            model: root.rightGroups
            delegate: Section {}
        }
    }
}
