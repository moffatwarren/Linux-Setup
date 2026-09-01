import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtQuick

// waybar: "pulseaudio".
//
// waybar keyed its format-icons off hardcoded sink IDs, which differ per machine
// (hence the PRESERVE entries in install.sh). Guessing the role from the sink
// name does not work either -- on this machine the headphones are the PCI analog
// jack and the speakers are USB, and other machines invert that.
//
// So the role -> sink mapping is read from audio-output-toggle.sh, which is
// already the machine-local source of truth for exactly this and is already
// preserved across updates. Anything that is not the headphone or bluetooth
// sink gets the volume ramp, matching waybar's "default".
Pill {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    readonly property real volume: audio ? audio.volume : 0
    readonly property bool muted: audio ? audio.muted : false
    readonly property string sinkName: sink ? String(sink.name) : ""

    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sourceAudio: source ? source.audio : null

    // description is the human-readable name ("Built-in Audio Analog Stereo");
    // nickname and name are fallbacks for nodes that publish neither.
    function nodeLabel(node) {
        if (!node) return "";
        if (node.description) return String(node.description);
        if (node.nickname) return String(node.nickname);
        return node.name ? String(node.name) : "";
    }

    property string headphoneSink: ""
    property string bluetoothSink: ""

    // All Material Design Icons out of the nerd font, so the glyph is flat
    // monochrome line art in the pill's own colour, matching the weather and
    // bluetooth modules. The speaker/headphone emoji this used to draw
    // (U+1F508..U+1F50A, U+1F3A7) come from the colour emoji font instead:
    // they ignore labelColor entirely and render as glossy multicolour blobs
    // next to everything else on the bar.
    readonly property string icon: {
        if (muted) return "\udb81\udf5f";                                  // volume-mute
        if (sinkName.length > 0 && sinkName === bluetoothSink) return "\udb80\udcb1";
        if (sinkName.indexOf("bluez") === 0) return "\udb80\udcb1";        // bluetooth-audio
        if (sinkName.length > 0 && sinkName === headphoneSink) return "\udb80\udecb";
        if (volume <= 0.01) return "\udb81\udd81";                         // volume-off
        if (volume < 0.34) return "\udb81\udd7f";                          // volume-low
        if (volume < 0.67) return "\udb81\udd80";                          // volume-medium
        return "\udb81\udd7e";                                             // volume-high
    }

    // Which sink is headphones/bluetooth is machine-specific; read it rather
    // than infer it. Re-read when the sink changes so a toggle is picked up.
    Process {
        id: roles
        running: true
        command: ["bash", "-lc",
                  "grep -E '^(HEADPHONE|BLUETOOTH)_SINK=' ~/.config/hypr/scripts/audio-output-toggle.sh || true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    const m = lines[i].match(/^(HEADPHONE|BLUETOOTH)_SINK="?([^"]*)"?/);
                    if (!m) continue;
                    if (m[1] === "HEADPHONE") root.headphoneSink = m[2];
                    else root.bluetoothSink = m[2];
                }
            }
        }
    }

    onSinkNameChanged: if (!roles.running) roles.running = true

    // Keeps the volume/mute/description properties of both defaults live.
    PwObjectTracker {
        objects: {
            const out = [];
            if (root.sink) out.push(root.sink);
            if (root.source) out.push(root.source);
            return out;
        }
    }

    label: sink ? (muted ? icon : icon + " " + Math.round(volume * 100) + "%") : ""
    labelColor: Theme.maroon

    onClicked: Quickshell.execDetached(["bash", "-lc", "~/.config/hypr/scripts/audio-output-toggle.sh"])
    onRightClicked: Quickshell.execDetached(["pavucontrol"])
    onScrolled: delta => {
        if (!audio) return;
        audio.muted = false;
        audio.volume = Math.max(0, Math.min(1, audio.volume + (delta > 0 ? 0.05 : -0.05)));
    }

    ListPopup {
        anchorItem: root
        requested: root.hovered
        title: "Audio"
        // Device descriptions run long ("Navi 48 HDMI/DP Audio Controller
        // Digital Stereo (HDMI 2) [27E3QKS]"); elide rather than let one row
        // stretch the panel across the screen.
        maxDetailWidth: 260
        rows: {
            const out = [];
            out.push({ text: "Output",
                       detail: root.sink ? root.nodeLabel(root.sink) : "none",
                       accent: root.sink ? Theme.text : Theme.subtext0 });
            if (root.audio)
                out.push({ text: "Volume",
                           detail: root.muted ? "muted" : Math.round(root.volume * 100) + "%",
                           accent: root.muted ? Theme.red : Theme.green });
            out.push({ text: "Input",
                       detail: root.source ? root.nodeLabel(root.source) : "none",
                       accent: root.source ? Theme.text : Theme.subtext0 });
            if (root.sourceAudio)
                out.push({ text: "Mic",
                           detail: root.sourceAudio.muted
                                   ? "muted" : Math.round(root.sourceAudio.volume * 100) + "%",
                           accent: root.sourceAudio.muted ? Theme.red : Theme.green });
            return out;
        }
    }
}
