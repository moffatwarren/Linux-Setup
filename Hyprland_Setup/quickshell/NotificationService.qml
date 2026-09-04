pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

// The notification daemon. Quickshell owns org.freedesktop.Notifications now --
// swaync is gone, because only one process can hold that bus name and swaync's
// own interface (org.erikreider.swaync.cc) exposes a count and a DND flag but
// no way to ask it what the notifications actually SAY. A bar module that lists
// them therefore has to be the server.
//
// A singleton because three things read it: NotificationPill (the count and the
// muted glyph), NotificationMenu (the list) and NotificationToasts (the popups).
//
// Two lists, deliberately not the same one:
//   entries -- what the menu shows, kept until dismissed. This is "unread".
//   popups  -- what is on screen right now, dropped on a timer.
// A notification leaves `popups` when its toast times out and stays in
// `entries`, which is exactly the difference between "you missed it" and "it is
// still shouting at you".
Singleton {
    id: root

    // ---- state -------------------------------------------------------------

    // Do not disturb. Persisted, so muting survives a bar restart -- a mute that
    // silently undoes itself on the next `install.sh` is worse than no mute.
    property bool dnd: false

    // [{ n: Notification, time: <ms since epoch> }], newest first.
    property var entries: []
    // Notifications currently drawn as toasts, oldest first (so they stack down
    // the screen in arrival order).
    property var popups: []

    readonly property int count: entries.length
    readonly property bool hasCritical: entries.some(e => e.n.urgency === NotificationUrgency.Critical)

    // Which monitor's NotificationMenu is open, "" for none. It lives here
    // rather than in the pill because there is one bar per monitor and SUPER+N
    // has to open exactly one of them -- see the `notifications` IpcHandler in
    // shell.qml.
    property string menuMonitor: ""

    // ---- timeouts ----------------------------------------------------------
    // The values the swaync config used (timeout 8 / timeout-low 3 /
    // timeout-critical 0), so the popups feel the same as before.
    readonly property int timeoutLow: 3000
    readonly property int timeoutNormal: 8000
    readonly property int timeoutCritical: 0     // 0 = stays until dismissed

    // ---- the server --------------------------------------------------------

    NotificationServer {
        id: server

        // Survive a config reload without dropping the list on the floor.
        keepOnReload: true

        // Advertised capabilities. actionIcons and inlineReply are off because
        // nothing here draws them; claiming a capability we do not implement
        // just makes apps send content that silently disappears.
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: false
        bodyHyperlinksSupported: false
        actionsSupported: true
        actionIconsSupported: false
        imageSupported: true
        inlineReplySupported: false

        // Hints without a dedicated property on Notification, and both are
        // load-bearing: `value` is the 0-100 the volume/brightness OSDs draw as
        // a progress bar, and x-canonical-private-synchronous is how those same
        // scripts say "replace the last one" -- notify-send sends no replaces_id,
        // so without this hint every volume tap would stack a new popup.
        // x-dunst-stack-tag is the other spelling of the same idea.
        extraHints: ["value", "x-canonical-private-synchronous", "x-dunst-stack-tag", "synchronous"]

        onNotification: notification => root.receive(notification)
    }

    // ---- classification ----------------------------------------------------

    // The OSD tag, or "" for an ordinary notification. hypr/scripts'
    // volume-notify.sh, brightness-notify.sh and audio-output-toggle.sh all set
    // it; a readout of your own keypress is not a message to come back to.
    function osdTag(n) {
        const h = n.hints ?? ({});
        return String(h["x-canonical-private-synchronous"]
                      ?? h["x-dunst-stack-tag"]
                      ?? h["synchronous"]
                      ?? "");
    }

    // Shown, but never listed. `transient` is the spec's own way of saying the
    // same thing, so it counts too.
    function isTransient(n) {
        return n.transient || root.osdTag(n).length > 0;
    }

    // The int:value hint the OSD scripts pass, or -1 when there is none.
    function progressOf(n) {
        const v = (n.hints ?? ({}))["value"];
        return v === undefined || v === null ? -1 : Math.max(0, Math.min(100, Number(v)));
    }

    // Quickshell reports the client's expire_timeout in MILLISECONDS: -1 means
    // "server decides" and 0 means "never expire" (brightness-notify.sh's
    // `-t 1500` arrives here as 1500).
    function timeoutFor(n) {
        if (n.expireTimeout === 0) return 0;
        if (n.expireTimeout > 0) return n.expireTimeout;
        switch (n.urgency) {
        case NotificationUrgency.Critical: return root.timeoutCritical;
        case NotificationUrgency.Low:      return root.timeoutLow;
        default:                           return root.timeoutNormal;
        }
    }

    function accentFor(urgency) {
        switch (urgency) {
        case NotificationUrgency.Critical: return Theme.red;
        case NotificationUrgency.Low:      return Theme.surface2;
        default:                           return Theme.blue;
        }
    }

    // ---- intake ------------------------------------------------------------

    function receive(n) {
        // Quickshell destroys a notification as soon as the signal handler
        // returns unless something claims it. Everything here is claimed --
        // even an OSD, which is dropped explicitly when its toast expires.
        n.tracked = true;

        const tag = root.osdTag(n);
        if (tag.length > 0) {
            // Replace rather than stack: holding a volume key should leave one
            // popup counting up, not thirty.
            for (const p of root.popups.slice()) {
                if (p !== n && root.osdTag(p) === tag) p.dismiss();
            }
        }

        // The list and the popup stack are both keyed on the object, so both
        // have to let go when the sending app closes it out from under us.
        n.closed.connect(() => root.forget(n));

        if (!root.isTransient(n))
            root.entries = [{ n: n, time: Date.now() }].concat(root.entries);

        // DND silences apps, not your own keypresses: an OSD still shows, and so
        // does a critical notification. Suppressing the volume popup while muted
        // makes the volume keys feel broken, which is not what "mute
        // notifications" is asking for.
        const show = !root.dnd
                     || tag.length > 0
                     || n.urgency === NotificationUrgency.Critical;

        if (show) root.popups = root.popups.concat([n]);
        else if (root.isTransient(n)) n.dismiss();   // nothing would ever show it
    }

    // Drop every reference to a notification that has gone away.
    function forget(n) {
        root.entries = root.entries.filter(e => e.n !== n);
        root.popups = root.popups.filter(p => p !== n);
    }

    // ---- actions -----------------------------------------------------------

    // The toast timed out. A listed notification just stops popping; a transient
    // one has nowhere left to live, so it goes for good.
    function hidePopup(n) {
        root.popups = root.popups.filter(p => p !== n);
        if (root.isTransient(n)) n.dismiss();
    }

    function dismiss(n) { n.dismiss(); }

    function clearAll() {
        // Snapshot first: every dismiss() re-enters forget() and rewrites the
        // array we would otherwise still be walking.
        for (const e of root.entries.slice()) e.n.dismiss();
    }

    function clearPopups() {
        for (const p of root.popups.slice()) root.hidePopup(p);
    }

    function toggleDnd() { root.dnd = !root.dnd; }

    function toggleMenu(monitor) {
        root.menuMonitor = root.menuMonitor === monitor ? "" : monitor;
    }

    function closeMenu() { root.menuMonitor = ""; }

    // Unconditional open, for the bar's hover hand-off: crossing the module
    // with another menu already up must open this one, never toggle it shut.
    function showMenu(monitor) { root.menuMonitor = monitor; }

    // ---- formatting --------------------------------------------------------

    // "now" / "3 min" / "2 h" / "4 d" -- what the menu puts down the right-hand
    // edge, in place of swaync's relative timestamps.
    function ago(time, now) {
        const secs = Math.max(0, Math.floor((now - time) / 1000));
        if (secs < 45) return "now";
        const mins = Math.round(secs / 60);
        if (mins < 60) return mins + " min";
        const hours = Math.round(mins / 60);
        if (hours < 24) return hours + " h";
        return Math.round(hours / 24) + " d";
    }

    // ---- persistence -------------------------------------------------------

    onDndChanged: dndFile.setText(JSON.stringify({ dnd: root.dnd }))

    FileView {
        id: dndFile

        path: Quickshell.env("HOME") + "/.cache/quickshell-notifications.json"
        preload: true
        // Absent until the first time DND is toggled; not worth an error on
        // every bar startup.
        printErrors: false

        onLoaded: {
            try {
                const parsed = JSON.parse(dndFile.text());
                if (parsed && typeof parsed === "object") root.dnd = parsed.dnd === true;
            } catch (e) {
                root.dnd = false;
            }
        }
    }
}
