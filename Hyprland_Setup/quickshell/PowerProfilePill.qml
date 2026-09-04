import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// waybar: "power-profiles-daemon" -- icon per profile, click cycles.
//
// **Left-click opens PowerProfileMenu now; the cycle moved to the right
// button.** The menu names the three profiles and carries the machine's vitals,
// which have no bar module of their own: CPU and memory, GPU load and VRAM,
// root filesystem use and the two temperatures. They were this pill's hover
// panel, and a panel is the one thing on this bar you cannot click into -- so
// the profile picker had nowhere to go until the panel became a menu.
//
// This file still samples everything and hands the menu the numbers and the
// formatters; the menu only draws them. That split matters more here than
// elsewhere: the CPU figure is a delta between two /proc/stat reads, so it has
// to be sampled whether or not anything is looking.
Pill {
    id: root

    readonly property int profile: PowerProfiles.profile

    // Icons are private-use nerd font codepoints copied from waybar's
    // format-icons, written as \u escapes so they survive editing.
    label: {
        switch (profile) {
        case PowerProfile.Performance: return "\uf0e7";
        case PowerProfile.Balanced:    return "\uf24e";
        case PowerProfile.PowerSaver:  return "\uf06c";
        default:                       return "\uf0e7";
        }
    }
    labelColor: profile === PowerProfile.Performance ? Theme.peach
              : profile === PowerProfile.PowerSaver ? Theme.green
              : Theme.text

    onClicked: {
        if (!menu.open) refreshStats();
        menu.open = !menu.open;
    }

    // Cycle saver -> balanced -> performance, skipping performance where
    // unsupported. This was the left button until the menu took it; it is kept
    // because it is still the fastest way to step the profile once you know the
    // order, the same menu/shortcut split BluetoothPill and NotificationPill use.
    onRightClicked: {
        if (profile === PowerProfile.PowerSaver) PowerProfiles.profile = PowerProfile.Balanced;
        else if (profile === PowerProfile.Balanced && PowerProfiles.hasPerformanceProfile) PowerProfiles.profile = PowerProfile.Performance;
        else PowerProfiles.profile = PowerProfile.PowerSaver;
    }

    // --- vitals -------------------------------------------------------------
    // system-stats.sh emits raw numbers (bytes / percent / millidegrees) and
    // omits anything it could not read, so a missing sensor drops its row
    // rather than reporting a plausible-looking zero. Sampling only runs while
    // the menu is open -- it is the only consumer, so an idle bar spawns
    // nothing. It was gated on `hovered` for exactly the same reason.
    property var stats: ({})

    function has(key) { return stats[key] !== undefined; }

    function humanBytes(bytes) {
        const gib = bytes / (1024 * 1024 * 1024);
        return gib >= 100 ? gib.toFixed(0) + " GiB" : gib.toFixed(1) + " GiB";
    }

    // Used/total plus the percentage, which is the number the eye actually wants.
    function usage(used, total) {
        if (!total) return "";
        return humanBytes(used) + " / " + humanBytes(total)
             + "  (" + Math.round(used / total * 100) + "%)";
    }

    function loadColor(percent) {
        return percent >= 90 ? Theme.red : percent >= 70 ? Theme.yellow : Theme.green;
    }

    // Celsius from the millidegrees every hwmon reports.
    function temp(milli) { return Math.round(milli / 1000) + "°C"; }

    function tempColor(milli) {
        const c = milli / 1000;
        return c >= 85 ? Theme.red : c >= 70 ? Theme.yellow : Theme.green;
    }

    Process {
        id: statsProc
        command: ["bash", "-lc", "~/.config/hypr/scripts/system-stats.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.stats = JSON.parse(text);
                } catch (e) {
                    // Keep the last good sample rather than blanking the panel.
                }
            }
        }
    }

    function refreshStats() { if (!statsProc.running) statsProc.running = true; }

    // One read on the way open, so the menu is populated the moment it appears
    // rather than two seconds later.
    Timer {
        interval: 2000
        running: menu.open
        repeat: true
        onTriggered: root.refreshStats()
    }

    // --- cpu ----------------------------------------------------------------
    // /proc/stat counts jiffies since boot, so utilisation is a delta between
    // two samples rather than a value that can be read once. FileView reads it
    // without spawning anything, which is cheap enough to sample continuously
    // -- and sampling continuously is what lets the panel show a real figure
    // the moment it opens, instead of a blank row until the second tick.
    property real cpuPct: -1
    property real lastCpuTotal: -1
    property real lastCpuIdle: -1

    FileView { id: statFile; path: "/proc/stat"; blockLoading: true }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            statFile.reload();
            const parts = statFile.text().split("\n")[0].trim().split(/\s+/);
            if (parts.length < 6) return;
            let total = 0;
            for (let i = 1; i < parts.length; i++) total += parseFloat(parts[i]);
            // idle + iowait are the only two fields that are not work done.
            const idle = parseFloat(parts[4]) + parseFloat(parts[5]);
            if (isNaN(total) || isNaN(idle)) return;
            const dTotal = total - root.lastCpuTotal;
            // reload() hands back the previous contents once at startup, and a
            // zero delta would divide by zero -- keep the last good figure.
            if (root.lastCpuTotal >= 0 && dTotal > 0)
                root.cpuPct = Math.max(0, Math.min(100, 100 * (1 - (idle - root.lastCpuIdle) / dTotal)));
            root.lastCpuTotal = total;
            root.lastCpuIdle = idle;
        }
    }

    PowerProfileMenu {
        id: menu
        anchorItem: root

        stats: root.stats
        cpuPct: root.cpuPct
        // Passed as functions rather than duplicated: they are the pill's own
        // idea of what counts as hot and what counts as loaded, and two copies
        // of a threshold drift.
        formatBytes: root.humanBytes
        formatUsage: root.usage
        loadColor: root.loadColor
        tempColor: root.tempColor
        formatTemp: root.temp
    }
}
