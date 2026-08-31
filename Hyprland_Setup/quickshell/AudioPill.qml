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

    property string headphoneSink: ""
    property string bluetoothSink: ""

    readonly property string icon: {
        if (muted) return "\ueb24";
        if (sinkName.length > 0 && sinkName === bluetoothSink) return "\udb86\udc52";
        if (sinkName.indexOf("bluez") === 0) return "\udb86\udc52";
        if (sinkName.length > 0 && sinkName === headphoneSink) return "\ud83c\udfa7";
        if (volume <= 0.01) return "\ud83d\udd08";
        if (volume < 0.5) return "\ud83d\udd09";
        return "\ud83d\udd0a";
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

    // Keeps the sink's volume/mute properties live.
    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
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
}
