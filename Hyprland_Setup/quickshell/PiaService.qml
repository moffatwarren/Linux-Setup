pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The PIA module's shared state: the shortlist of regions the menu offers, and
// the names it draws them with.
//
// A singleton for the same reason AudioService, NotificationService and
// RecorderService are. There is one Bar -- and so one PiaPill and one PiaMenu --
// per monitor, they all have to agree about the shortlist, and only one of them
// may own the file it is written to (~/.cache/quickshell-pia.json).
//
// **The shortlist is what you have actually used, not a committed list of
// places.** PIA publishes 190 regions and the useful five are a property of the
// person, not of the machine or the repo -- which is precisely the value this
// repo does not put in a config file (see "Nothing is machine-specific any
// more"). So picking a region records it, and the menu offers the five most
// recent ones under `auto`. `seedRegions` only fills the gap before there are
// five: a fresh machine gets a usable list on day one instead of a lone `auto`
// with nothing under it, and each real choice pushes one of the seeds out.
//
// The full picker is the PIA client, which the menu's footer opens -- this is a
// shortcut, deliberately not a replacement for it.
Singleton {
    id: root

    readonly property string script: "~/.config/hypr/scripts/pia.sh"
    readonly property int shortlistLength: 5

    // Widely-used regions spread across the map, only ever used to pad the
    // shortlist out to five. One line to change, and nothing depends on them
    // being right for you -- they are gone after five picks of your own.
    readonly property var seedRegions: ["us-east", "us-west", "uk-london",
                                        "ca-toronto", "de-frankfurt"]

    // Region ids, most recently chosen first.
    property var recents: []
    // Everything piactl reports, so a seed (or a stale recent) that PIA has
    // retired is dropped rather than offered as a button that cannot work.
    // Empty means "not asked yet, or the daemon is down" -- in which case
    // nothing is filtered, since an empty list is not evidence of absence.
    property var knownRegions: []
    property bool loaded: false

    // `auto` is never in this list: the menu pins it above, always, because it
    // is the one entry that is not a place and cannot be forgotten.
    readonly property var shortlist: {
        const out = [];
        const seen = ({});
        const known = ({});
        for (var k = 0; k < knownRegions.length; k++) known[knownRegions[k]] = true;
        const usable = id => id !== "auto" && !seen[id]
                             && (knownRegions.length === 0 || known[id] === true);

        for (var i = 0; i < recents.length && out.length < shortlistLength; i++) {
            if (!usable(recents[i])) continue;
            seen[recents[i]] = true;
            out.push(recents[i]);
        }
        for (var j = 0; j < seedRegions.length && out.length < shortlistLength; j++) {
            if (!usable(seedRegions[j])) continue;
            seen[seedRegions[j]] = true;
            out.push(seedRegions[j]);
        }
        return out;
    }

    // piactl prints ids (`us-salt-lake-city`); PIA's own name for that region is
    // "US Salt Lake City". Derived rather than looked up: the published server
    // list does carry real names, but its ids only agree with piactl's for about
    // three quarters of the regions, so joining the two would silently leave a
    // quarter of the menu unnamed. A leading two-letter token is a country code
    // and is upper-cased; everything else is a word.
    function regionName(id) {
        if (!id || id === "auto") return "Automatic";
        return String(id).split("-").map((part, index) =>
            index === 0 && part.length === 2
                ? part.toUpperCase()
                : part.charAt(0).toUpperCase() + part.slice(1)
        ).join(" ");
    }

    function remember(id) {
        if (!id || id === "auto") return;
        const next = [String(id)];
        for (var i = 0; i < recents.length; i++)
            if (recents[i] !== id) next.push(recents[i]);
        // Twice the shortlist is kept, so a region that falls off the visible
        // five comes back to the top when it is chosen from the PIA client
        // rather than being forgotten the moment it scrolls off.
        recents = next.slice(0, shortlistLength * 2);
        save();
    }

    // One process for every bar, asked when a menu opens rather than polled --
    // the region list changes about as often as PIA adds a country.
    function refreshRegions() {
        if (!regionsProc.running) regionsProc.running = true;
    }

    Process {
        id: regionsProc
        command: ["bash", "-lc", root.script + " --regions"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Region ids are single words. The space check is not
                // pedantry: an older deployed pia.sh that has never heard of
                // --regions prints its usage line on stdout, which would
                // otherwise become a one-entry "known regions" list that
                // filters the whole shortlist away. Verified -- it is exactly
                // what happens against a stale copy of the script.
                const list = text.split("\n").map(l => l.trim())
                                 .filter(l => l.length > 0 && l.indexOf(" ") === -1);
                // Nothing means the daemon is down, or the script is too old to
                // answer; keep the last good list rather than emptying the menu.
                if (list.length > 0) root.knownRegions = list;
            }
        }
    }

    function save() {
        if (!loaded) return;
        stateFile.setText(JSON.stringify({ recentRegions: recents }, null, 1));
    }

    FileView {
        id: stateFile

        path: Quickshell.env("HOME") + "/.cache/quickshell-pia.json"
        preload: true
        atomicWrites: true
        // Absent until the first region is picked; not worth an error on every
        // bar startup.
        printErrors: false

        onLoaded: {
            try {
                const parsed = JSON.parse(stateFile.text());
                const list = parsed && parsed.recentRegions ? parsed.recentRegions : [];
                root.recents = list.map(x => String(x)).filter(x => x.length > 0);
            } catch (e) {
                // Truncated or hand-edited: start over rather than refuse to
                // save for the rest of the session.
                root.recents = [];
            }
            root.loaded = true;
        }

        // No file yet, which is the normal case -- and saving has to be
        // unblocked here too or it never starts. Same trap as AudioService.
        onLoadFailed: root.loaded = true
    }
}
