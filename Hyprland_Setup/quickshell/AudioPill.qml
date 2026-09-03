import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// waybar: "pulseaudio".
//
// waybar keyed its format-icons off hardcoded sink IDs, which differ per machine
// (hence the PRESERVE entries install.sh used to carry for this). Guessing the
// role from the sink name does not work either -- on this machine the headphones
// are the PCI analog jack and the speakers are USB, and other machines invert
// that -- which is why the icon is now a per-sink choice made in AudioMenu and
// remembered by AudioService, rather than anything this file works out.
//
// The default choice, `volume`, is the ramp waybar's "default" drew: the glyph
// follows the level. Any other choice is a fixed glyph, because an output you
// have named is better identified than measured.
Pill {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    readonly property real volume: audio ? audio.volume : 0
    readonly property bool muted: audio ? audio.muted : false
    readonly property string sinkName: sink ? String(sink.name) : ""

    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sourceAudio: source ? source.audio : null

    // All Material Design Icons out of the nerd font, so the glyph is flat
    // monochrome line art in the pill's own colour, matching the weather and
    // bluetooth modules. The speaker/headphone emoji this used to draw
    // (U+1F508..U+1F50A, U+1F3A7) come from the colour emoji font instead:
    // they ignore labelColor entirely and render as glossy multicolour blobs
    // next to everything else on the bar.
    readonly property string icon: {
        if (muted) return "\udb81\udf5f";                                  // volume-mute
        const key = sinkName.length > 0 ? AudioService.iconKey(sinkName) : "volume";
        if (key !== "volume") return AudioService.iconChoice(key).glyph;
        if (volume <= 0.01) return "\udb81\udd81";                         // volume-off
        if (volume < 0.34) return "\udb81\udd7f";                          // volume-low
        if (volume < 0.67) return "\udb81\udd80";                          // volume-medium
        return "\udb81\udd7e";                                             // volume-high
    }

    // Keeps the volume/mute/description properties of both defaults live.
    // AudioService tracks every other node, for the menu.
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

    // Left opens the output/input picker, right mutes -- the same menu/shortcut
    // split BluetoothPill uses (left opens the device list, right toggles the
    // adapter). pavucontrol moved from this right-click into the menu's footer,
    // beside blueman's.
    //
    // Mute is set straight on the node, the way onScrolled already sets volume,
    // rather than shelling out to volume-notify.sh: no process, and no OSD --
    // the glyph you just clicked is the feedback.
    onClicked: audioMenu.open = !audioMenu.open
    onRightClicked: if (audio) audio.muted = !audio.muted
    // 1% a notch, matching what XF86AudioRaise/LowerVolume do via
    // volume-notify.sh (`wpctl set-volume … 1%+`), so a wheel notch and a key
    // press are the same step.
    onScrolled: delta => {
        if (!audio) return;
        audio.muted = false;
        audio.volume = Math.max(0, Math.min(1, audio.volume + (delta > 0 ? 0.01 : -0.01)));
    }

    AudioMenu {
        id: audioMenu
        anchorItem: root
    }

    ListPopup {
        anchorItem: root
        requested: root.hovered && !audioMenu.open
        title: "Audio"
        // Device descriptions run long ("Navi 48 HDMI/DP Audio Controller
        // Digital Stereo (HDMI 2) [27E3QKS]"); elide rather than let one row
        // stretch the panel across the screen.
        maxDetailWidth: 260
        rows: {
            const out = [];
            out.push({ text: "Output",
                       detail: root.sink ? AudioService.nodeLabel(root.sink) : "none",
                       accent: root.sink ? Theme.text : Theme.subtext0 });
            if (root.audio)
                out.push({ text: "Volume",
                           detail: root.muted ? "muted" : Math.round(root.volume * 100) + "%",
                           accent: root.muted ? Theme.red : Theme.green });
            out.push({ text: "Input",
                       detail: root.source ? AudioService.nodeLabel(root.source) : "none",
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
