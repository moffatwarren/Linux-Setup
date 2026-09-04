import Quickshell
import Quickshell.Services.UPower
import QtQuick

// waybar: "battery" -- icon ramp, red under 30%, charging bolt.
// Hidden entirely on machines with no battery (this desktop reports none),
// which is what the empty label achieves via Pill.visible.
//
// Left-click opens the detail panel. It was a hover panel, and moving it onto
// the button is the same trade CalendarPopup and ForecastPopup made: a panel
// that appears because the pointer crossed the pill also vanishes because the
// pointer left it, so it cannot be read at leisure and cannot be dismissed by
// any means except moving away. Opened by a click it dismisses like every other
// drop-down here -- Escape, or a click anywhere outside -- which is what
// ListPopup's `dismissable` turns on.
Pill {
    id: root

    readonly property var battery: UPower.displayDevice
    readonly property bool present: battery && battery.isPresent && battery.isLaptopBattery
    readonly property real percent: battery ? battery.percentage * 100 : 0
    readonly property bool charging: battery && battery.state === UPowerDeviceState.Charging

    readonly property string icon: {
        const icons = ["\uf244", "\uf243", "\uf242", "\uf241", "\uf240"];
        const i = Math.min(icons.length - 1, Math.floor(percent / 20));
        return icons[Math.max(0, i)];
    }

    label: present ? Math.round(percent) + "% " + (charging ? "\uf5e7" : icon) : ""
    labelColor: (percent <= 30 && !charging) ? Theme.red : Theme.green

    function duration(seconds) {
        if (!seconds || seconds <= 0) return "unknown";
        const h = Math.floor(seconds / 3600);
        const m = Math.round((seconds % 3600) / 60);
        return h > 0 ? h + "h " + m + "m" : m + "m";
    }

    // The flag lives on the popup rather than on the pill, the way ClockPill
    // drives CalendarPopup.
    onClicked: if (present) panel.open = !panel.open

    ListPopup {
        id: panel

        property bool open: false

        anchorItem: root
        dismissable: true
        // No open delay: the 300 ms exists to stop a panel flashing up as the
        // pointer crosses the pill, and a panel you asked for should not wait.
        delayMs: 0
        requested: panel.open && root.present
        onDismissed: panel.open = false
        title: root.battery && root.battery.model ? String(root.battery.model) : "Battery"
        rows: {
            if (!root.present) return [];
            const out = [
                { text: "Charge", detail: Math.round(root.percent) + "%",
                  accent: root.percent <= 30 && !root.charging ? Theme.red : Theme.green },
                { text: "State", detail: root.charging ? "charging" : "discharging",
                  accent: root.charging ? Theme.green : Theme.subtext0 }
            ];
            out.push(root.charging
                ? { text: "Full in", detail: root.duration(root.battery.timeToFull) }
                : { text: "Empty in", detail: root.duration(root.battery.timeToEmpty) });
            if (root.battery.healthSupported)
                out.push({ text: "Health", detail: Math.round(root.battery.healthPercentage) + "%" });
            return out;
        }
    }
}
