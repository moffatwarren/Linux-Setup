pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// The audio module's shared state: which outputs are in the SUPER+O rotation,
// and which outputs this machine has ever seen.
//
// A singleton for the same reason NotificationService and RecorderService are.
// There is one Bar -- and so one AudioPill and one AudioMenu -- per monitor, and
// all of them have to agree about the rotation; more to the point, only one of
// them may own the file it is written to.
//
// ~/.cache/quickshell-audio.json is read by hypr/scripts/audio-output-toggle.sh
// as well, which is what actually performs the SUPER+O cycle. The bar is the
// only writer. Its shape:
//
//   { "outputs": [ { "name": …, "description": …, "enabled": true, "icon": … }, … ] }
//
// A sink with no record at all counts as enabled, so a machine that has never
// opened the menu still cycles everything -- and a sink that appears for the
// first time joins the rotation rather than being silently skipped.
//
// A record outlives its sink: unplugging a headset does not drop what its
// switch was set to, so plugging it back in restores the rotation as it was.
// The menu, though, lists only what is plugged in -- a row for an absent output
// is a switch that changes nothing, since SUPER+O steps through present sinks
// and can never land on it. So `records` is the memory and `outputs` is the
// menu, and they are deliberately not the same list.
//
// `icon` is the glyph the bar draws for that output, picked in the menu. It
// replaced reading HEADPHONE_SINK/BLUETOOTH_SINK out of audio-output-toggle.sh,
// which meant the answer had to be edited in a shell script, was one of only two
// role names the machine could express, and needed a PRESERVE entry to survive a
// deploy. The whole reason that read existed is that a sink's role cannot be
// inferred from its name -- on this machine the headphones are the PCI analog
// jack and the speakers are USB, and other machines invert that -- and the fix
// for something that cannot be inferred is to be told it once, by the person
// looking at the hardware, and to remember. Absent, it is inferred anyway (see
// defaultIconKey) because a default has to come from somewhere.
Singleton {
    id: root

    // Sorted by node id, which is the same number pactl prints as the sink
    // index -- so the menu lists outputs in exactly the order the script cycles
    // them. isStream drops per-application streams; the audio check drops video
    // nodes. Monitor sources are ports on a sink rather than nodes, so nothing
    // has to filter those out here (pactl synthesises them; PipeWire does not).
    readonly property var sinks: uniqueByName(Pipewire.nodes.values
        .filter(n => n.isSink && !n.isStream && n.audio)
        .sort((a, b) => a.id - b.id))

    readonly property var sources: uniqueByName(Pipewire.nodes.values
        .filter(n => !n.isSink && !n.isStream && n.audio)
        .sort((a, b) => a.id - b.id))

    // A node name is unique in the menu but NOT in PipeWire. Unplugging and
    // replugging a monitor while the session runs leaves WirePlumber's old HDMI
    // sink node behind beside the new one -- verified after two hotplugs: three
    // nodes (ids 54, 107, 108), same node.name, same device, same
    // api.alsa.path, all reported by pactl and by Pipewire.nodes. They are the
    // same ALSA pcm, so the extras are ghosts and the menu drew the monitor
    // three times.
    //
    // Everything downstream is keyed by name already (records, the icon, the
    // default-sink comparison, and the state file this writes), so deduping the
    // node list here is the whole fix. Which of the duplicates is kept barely
    // matters -- the default sink is set by name, so a ghost cannot be selected
    // by mistake -- and the first, i.e. the lowest node id after the sort above,
    // is the one that keeps the menu's order stable as ghosts come and go.
    function uniqueByName(nodes) {
        const seen = ({});
        const out = [];
        for (var i = 0; i < nodes.length; i++) {
            const name = String(nodes[i].name);
            if (seen[name]) continue;
            seen[name] = true;
            out.push(nodes[i]);
        }
        return out;
    }

    // name -> { description, enabled }. Everything ever seen, present or not.
    property var records: ({})
    // Nothing may be written before the file has been read, or the first sink
    // to arrive at startup would clobber the saved rotation with defaults.
    property bool loaded: false

    // description is the human-readable name ("Built-in Audio Analog Stereo");
    // nickname and name are fallbacks for nodes that publish neither.
    function nodeLabel(node) {
        if (!node) return "";
        if (node.description) return String(node.description);
        if (node.nickname) return String(node.nickname);
        return node.name ? String(node.name) : "";
    }

    // No record means enabled: see the file-shape note above.
    function isEnabled(name) {
        const record = records[name];
        return !record || record.enabled !== false;
    }

    function setEnabled(name, on) {
        const next = Object.assign({}, records);
        const prev = next[name];
        next[name] = { description: prev ? prev.description : name,
                       enabled: on === true,
                       icon: prev ? prev.icon : undefined };
        records = next;
        save();
    }

    // What the menu lists: the sinks that are plugged in right now, with the
    // toggle state remembered for each. Outputs that have been seen before and
    // are not here are still in `records` -- they are just not shown, because
    // their switch could not affect anything until they are back.
    readonly property var outputs: sinks.map(node => {
        const name = String(node.name);
        return { name: name, description: nodeLabel(node), node: node,
                 enabled: isEnabled(name), icon: iconKey(name) };
    })

    readonly property int enabledCount: outputs.filter(o => o.enabled).length

    function setDefaultSink(node) { if (node) Pipewire.preferredDefaultAudioSink = node; }
    function setDefaultSource(node) { if (node) Pipewire.preferredDefaultAudioSource = node; }

    // The icon palette, in the order AudioMenu draws it. `volume` is the
    // default and the only one that is not a fixed glyph: it means "no choice
    // made", and follows the volume level the way the pill always has.
    //
    // Nerd font private-use codepoints, so \uXXXX escapes -- pasting the glyph
    // itself silently yields an empty string and the module vanishes.
    readonly property var iconChoices: [
        { key: "volume",     glyph: "\udb81\udd7e", label: "Volume" },
        { key: "speaker",    glyph: "\udb81\udcc3", label: "Speakers" },
        { key: "headphones", glyph: "\udb80\udecb", label: "Headphones" },
        { key: "bluetooth",  glyph: "\udb80\udcb1", label: "Bluetooth" },
        { key: "display",    glyph: "\udb83\udf5f", label: "Display" },
        { key: "tv",         glyph: "\udb81\udd02", label: "TV" }
    ]

    // Only what a name can actually settle. Bluetooth and HDMI say what they are
    // in the sink name; headphones-versus-speakers does not, which is exactly
    // the distinction the menu exists to let you make.
    function defaultIconKey(name) {
        if (name.indexOf("bluez") === 0) return "bluetooth";
        if (name.indexOf("hdmi") !== -1 || name.indexOf("displayport") !== -1) return "display";
        return "volume";
    }

    function iconKey(name) {
        const record = records[name];
        if (record && record.icon) return String(record.icon);
        return defaultIconKey(name);
    }

    function iconChoice(key) {
        for (var i = 0; i < iconChoices.length; i++)
            if (iconChoices[i].key === key) return iconChoices[i];
        return iconChoices[0];
    }

    // The menu's per-row glyph. `volume` draws the full-volume glyph here rather
    // than following the level: a row is naming an output, not reporting on it,
    // and only the default sink has a level worth showing anyway.
    function glyphFor(name) { return iconChoice(iconKey(name)).glyph; }

    function setIcon(name, key) {
        const next = Object.assign({}, records);
        const prev = next[name];
        next[name] = { description: prev ? prev.description : name,
                       enabled: prev ? prev.enabled !== false : true,
                       icon: key };
        records = next;
        save();
    }

    // Keeps description, volume and mute live on every node the menu draws --
    // an untracked PwNode publishes none of them.
    PwObjectTracker {
        objects: root.sinks.concat(root.sources)
    }

    // A sink that has never been seen is merged in with its toggle on, so the
    // file is a complete record of this machine's outputs rather than only of
    // the ones whose switch has been touched.
    function save() {
        if (!loaded) return;
        const merged = ({});
        for (const name in records)
            merged[name] = { description: records[name].description || name,
                             enabled: records[name].enabled !== false,
                             icon: records[name].icon };
        for (var i = 0; i < sinks.length; i++) {
            const name = String(sinks[i].name);
            merged[name] = { description: nodeLabel(sinks[i]) || name,
                             enabled: merged[name] ? merged[name].enabled : true,
                             icon: merged[name] ? merged[name].icon : undefined };
        }
        records = merged;

        // An unset icon is left OUT of the file rather than written as its
        // inferred value: the inference can improve, and a machine that never
        // touched the picker should follow it rather than be pinned to whatever
        // it happened to say on the day the record was created.
        const list = [];
        for (const name in merged) {
            const entry = { name: name, description: merged[name].description,
                            enabled: merged[name].enabled };
            if (merged[name].icon) entry.icon = merged[name].icon;
            list.push(entry);
        }
        stateFile.setText(JSON.stringify({ outputs: list }, null, 1));
    }

    // Sinks arrive one at a time as PipeWire enumerates them at startup, and a
    // node's description lands after the node itself, so a save per change
    // would be a burst of writes ending in the only one that was complete.
    onSinksChanged: if (loaded) saveTimer.restart()
    onLoadedChanged: if (loaded) saveTimer.restart()

    Timer {
        id: saveTimer
        interval: 800
        onTriggered: root.save()
    }

    FileView {
        id: stateFile

        path: Quickshell.env("HOME") + "/.cache/quickshell-audio.json"
        preload: true
        atomicWrites: true
        // Absent until the bar first saves; not worth an error on every startup.
        printErrors: false

        onLoaded: {
            const next = ({});
            try {
                const parsed = JSON.parse(stateFile.text());
                const list = parsed && parsed.outputs ? parsed.outputs : [];
                for (var i = 0; i < list.length; i++) {
                    const entry = list[i];
                    if (!entry || !entry.name) continue;
                    next[String(entry.name)] = {
                        description: entry.description ? String(entry.description) : String(entry.name),
                        enabled: entry.enabled !== false,
                        icon: entry.icon ? String(entry.icon) : undefined
                    };
                }
            } catch (e) {
                // A truncated or hand-edited file: start over rather than
                // refuse to save for the rest of the session.
            }
            root.records = next;
            root.loaded = true;
        }

        // No file yet (the usual case on a new machine) -- that is the empty
        // record set, and saving has to be unblocked or it never starts.
        onLoadFailed: root.loaded = true
    }
}
