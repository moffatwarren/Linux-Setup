import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

// Left-click dropdown on the power-profile module: pick the profile at the top,
// read the machine's vitals underneath.
//
// The vitals were this pill's hover panel, and they are the reason the module
// gets a menu at all -- they have no bar module of their own, so a panel was
// the only place they could live, and a panel is the one thing on this bar you
// cannot click into. Moving them here is the same trade `WifiMenu` made.
//
// The profiles were a **cycle** on the pill: click, and it stepped
// saver -> balanced -> performance. Three named rows say which one is in force
// without having to read a glyph, and get to any of them in one click instead
// of up to three. The cycle is still on the pill's right button, because it is
// genuinely the faster gesture once you know the order.
//
// It owns no state: PowerProfilePill samples, this draws, the split every other
// menu on this bar uses.
PopupWindow {
    id: root

    property Item anchorItem: null
    property bool open: false

    // Raw numbers from system-stats.sh plus the CPU figure the pill differences
    // out of /proc/stat, and the formatters that turn them into rows.
    property var stats: ({})
    property real cpuPct: -1
    property var formatBytes: null
    property var formatUsage: null
    property var loadColor: null
    property var tempColor: null
    property var formatTemp: null

    readonly property var profiles: {
        const out = [
            { profile: PowerProfile.PowerSaver,  label: "Power Saver", glyph: "\uf06c",
              accent: Theme.green },
            { profile: PowerProfile.Balanced,    label: "Balanced",    glyph: "\uf24e",
              accent: Theme.text }
        ];
        // Not every machine has it, and a row that cannot be selected is worse
        // than one that is not offered -- the pill's cycle skips it for the
        // same reason.
        if (PowerProfiles.hasPerformanceProfile)
            out.push({ profile: PowerProfile.Performance, label: "Performance",
                       glyph: "\uf0e7", accent: Theme.peach });
        return out;
    }

    // power-profiles-daemon reports when it is holding performance back. Worth
    // a line, because otherwise picking Performance looks like it did nothing.
    readonly property string degradation: {
        switch (PowerProfiles.degradationReason) {
        case PerformanceDegradationReason.LapDetected:    return "Throttled: lap detected";
        case PerformanceDegradationReason.HighTemperature: return "Throttled: high temperature";
        default: return "";
        }
    }

    function has(key) { return stats[key] !== undefined; }

    readonly property var statRows: {
        const s = root.stats;
        const out = [];
        // Each processor's load paired with its own temperature, then the
        // capacity rows.
        if (root.cpuPct >= 0)
            out.push({ text: "CPU", detail: Math.round(root.cpuPct) + "%",
                       accent: root.loadColor(root.cpuPct) });
        if (has("cpu_temp"))
            out.push({ text: "CPU temp", detail: root.formatTemp(s.cpu_temp),
                       accent: root.tempColor(s.cpu_temp) });
        if (has("gpu_pct"))
            out.push({ text: "GPU", detail: s.gpu_pct + "%",
                       accent: root.loadColor(s.gpu_pct) });
        if (has("gpu_temp"))
            out.push({ text: "GPU temp", detail: root.formatTemp(s.gpu_temp),
                       accent: root.tempColor(s.gpu_temp) });
        if (has("ram_total"))
            out.push({ text: "RAM", detail: root.formatUsage(s.ram_used, s.ram_total),
                       accent: root.loadColor(s.ram_used / s.ram_total * 100) });
        if (has("vram_total"))
            out.push({ text: "VRAM", detail: root.formatUsage(s.vram_used, s.vram_total),
                       accent: root.loadColor(s.vram_used / s.vram_total * 100) });
        if (has("disk_total"))
            out.push({ text: "Disk", detail: root.formatUsage(s.disk_used, s.disk_total),
                       accent: root.loadColor(s.disk_used / s.disk_total * 100) });
        return out;
    }

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 6

    // Wide enough for "12.3 GiB / 31.3 GiB  (39%)" opposite its label without
    // the usage rows setting the width one at a time as they arrive.
    implicitWidth: 280
    implicitHeight: body.implicitHeight + 20
    color: "transparent"
    visible: open
    // Take the keyboard while open so Escape can close the menu.
    grabFocus: open

    // Dismiss on a click anywhere outside, as every other dropdown here does.
    HyprlandFocusGrab {
        windows: [root]
        active: root.open
        onCleared: root.close()
    }

    function close() { open = false; }

    Rectangle {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.close()
        radius: 12
        color: Theme.base
        border.width: 1
        border.color: Theme.surface1

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 5

            Text {
                text: "Power profile"
                color: Theme.lavender
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface1 }

            Repeater {
                model: root.profiles

                Rectangle {
                    id: profileRow

                    required property var modelData
                    readonly property bool current: PowerProfiles.profile === profileRow.modelData.profile

                    Layout.fillWidth: true
                    implicitHeight: 24
                    radius: 6
                    color: profileMouse.containsMouse ? Theme.surface0 : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6
                        anchors.rightMargin: 6
                        spacing: 8

                        // The radio dot PiaMenu's region rows use: exactly one
                        // of these is in force at a time.
                        Rectangle {
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            antialiasing: true
                            color: profileRow.current ? profileRow.modelData.accent : "transparent"
                            border.width: profileRow.current ? 0 : 1
                            border.color: Theme.surface2
                        }

                        // The same glyph the pill draws for this profile, so
                        // the bar and the menu cannot disagree about which is
                        // which.
                        Text {
                            text: profileRow.modelData.glyph
                            color: profileRow.current ? profileRow.modelData.accent : Theme.overlay0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }

                        Text {
                            Layout.fillWidth: true
                            text: profileRow.modelData.label
                            color: profileRow.current ? Theme.text : Theme.subtext0
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                    }

                    MouseArea {
                        id: profileMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // The menu stays open: switching profile is the sort of
                        // thing you do while watching the temperatures below.
                        onClicked: PowerProfiles.profile = profileRow.modelData.profile
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.degradation.length > 0
                text: root.degradation
                wrapMode: Text.Wrap
                color: Theme.yellow
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }

            // --- vitals ------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: 1
                color: Theme.surface1
            }

            Text {
                Layout.fillWidth: true
                visible: root.statRows.length === 0
                text: "Reading sensors\u2026"
                color: Theme.subtext0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Repeater {
                model: root.statRows

                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 16

                    Text {
                        text: modelData.text
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: modelData.detail
                        horizontalAlignment: Text.AlignRight
                        color: modelData.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }
            }
        }
    }
}
