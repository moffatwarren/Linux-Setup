import Quickshell
import Quickshell.Services.UPower
import QtQuick

// Low-battery warnings, as real notifications.
//
// The bar owns org.freedesktop.Notifications (NotificationService.qml), so
// these go out through notify-send like any other app's would: they pop as a
// toast, they land in the notification centre, and a critical one never
// expires, so a warning raised while the lid was shut is still there on the
// list when you open it.
//
// Instantiated ONCE, in shell.qml, deliberately not inside BatteryPill: there
// is one Bar (and so one BatteryPill) per monitor, and a two-monitor machine
// would otherwise raise every warning twice. Same reason NotificationToasts is
// not a Variants over screens.
QtObject {
    id: root

    readonly property var battery: UPower.displayDevice
    readonly property bool present: battery && battery.isPresent && battery.isLaptopBattery
    readonly property real percent: battery ? battery.percentage * 100 : 0
    // Charging OR fully charged OR on AC and idle -- anything but actually
    // draining. Warning about 8% while the charger is in is just noise.
    readonly property bool discharging: present
                                        && battery.state === UPowerDeviceState.Discharging

    // Descending, and each fires at most once per discharge cycle. Not
    // deduplicated with the x-canonical-private-synchronous hint the volume OSD
    // uses: that hint marks a notification transient, which keeps it OUT of the
    // notification list -- the opposite of what a battery warning is for.
    readonly property var levels: [
        { at: 20, urgency: "normal",   summary: "Battery low" },
        { at: 10, urgency: "critical", summary: "Battery very low" },
        { at: 5,  urgency: "critical", summary: "Battery critical" }
    ]

    // The lowest threshold already announced this cycle, 101 for none.
    property int lastFired: 101

    function timeLeft() {
        const secs = root.battery ? root.battery.timeToEmpty : 0;
        if (!secs || secs <= 0) return "";
        const h = Math.floor(secs / 3600);
        const m = Math.round((secs % 3600) / 60);
        return h > 0 ? h + "h " + m + "m left" : m + "m left";
    }

    function notify(level) {
        const pct = Math.round(root.percent);
        const left = root.timeLeft();
        const body = left.length > 0
                     ? pct + "% remaining — " + left
                     : pct + "% remaining";

        // No -i: the battery icons in the theme are *-symbolic SVGs with a
        // near-black fill baked in, which is invisible on a `base` card (the
        // same trap the volume OSD hit). With no icon NotificationToasts falls
        // back to its own glyph in the urgency accent -- a red warning triangle
        // for the critical ones, which is what this should look like anyway.
        Quickshell.execDetached([
            "notify-send",
            "-a", "battery",
            "-u", level.urgency,
            level.summary,
            body
        ]);
    }

    // A plain binding, not a timer: UPower pushes percentage changes, so this
    // re-evaluates exactly when the reading moves.
    onPercentChanged: root.check()
    onDischargingChanged: root.check()

    function check() {
        if (!root.present) return;

        // Plugged in: re-arm, so the next time it comes off the charger the
        // warnings work again.
        if (!root.discharging) {
            root.lastFired = 101;
            return;
        }

        // The DEEPEST threshold crossed, not the first one found: `levels` is
        // descending, so the last match wins. A resume from suspend can land
        // the reading below two of them at once, and "Battery low, 4%" is the
        // wrong card to raise in that case.
        let target = null;
        for (const level of root.levels)
            if (root.percent <= level.at) target = level;

        if (target && root.lastFired > target.at) {
            root.lastFired = target.at;
            root.notify(target);
        }
    }
}
