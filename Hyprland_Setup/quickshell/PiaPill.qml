import Quickshell
import Quickshell.Io
import QtQuick

// A padlock, closed and green when the tunnel is up, open and in the bar's
// normal text colour when it is not, and outlined in yellow while it is moving
// between the two.
//
// **PIA's own artwork is one file and it is not usable here.** The package ships
// /usr/share/pixmaps/piavpn.png and nothing else: a 256px full-colour raster of
// their padlock mascot, face and all. The connected/disconnected variants the
// client shows in a tray live inside its Qt resource bundle, not on disk. That
// one file is the wrong thing twice over -- it is a single image where two
// states are wanted, and it is multicolour, which is the trap the audio module
// already hit with emoji: it would ignore labelColor and sit on the bar as the
// only coloured thing on it. So the mark is Material Design's padlock pair from
// the nerd font, which is the shape PIA's logo is, in the family every other
// module here draws from.
//
// **Left-click opens the menu, and nothing else is bound.** Starting the daemon
// was the right-click and connecting was the double-click; both are buttons in
// the menu now, next to the region shortlist a mouse gesture had nowhere to put.
// So none of ScriptPill's three command properties are set and its handlers all
// run `run("")`, which is a no-op.
//
// pia.sh drives the state, whether its daemon is even up, starting that daemon,
// connecting, and the region list. This file runs it and holds the answers; the
// menu only draws them.
//
// `piactl get region` reports the *selected* region, which is usually "auto",
// so the public IP is what actually says where you are exiting.
ScriptPill {
    id: root

    readonly property bool connected: rawAlt === "connected"
    readonly property string script: PiaService.script

    command: script + " --status"

    // connecting / disconnecting, which pia.sh reports itself. The pill used to
    // be two colours because a hover panel named the transitional state in
    // words; that panel is a menu now, and a menu you have not opened says
    // nothing, so the third colour is back.
    readonly property bool busy: rawAlt === "connecting" || rawAlt === "disconnecting"

    // Hidden until the first poll lands, and on a machine with no PIA at all:
    // Pill drops a module with no label.
    label: rawAlt.length > 0 && !serviceAbsent ? icon : ""
    labelColor: connected ? Theme.green : busy ? Theme.yellow : Theme.text

    // md-lock / md-lock-open / md-lock-outline. Nerd Fonts v3 codepoints, which
    // live above U+F0000 and so must be written as surrogate pairs -- pasting
    // the glyph itself yields an empty string and Pill then hides the module,
    // which reads as a broken module rather than a broken label.
    readonly property string icon: connected ? "\udb80\udf3e"
                                 : busy ? "\udb80\udf41"
                                 : "\udb80\udf3f"

    // `systemctl is-active piavpn.service`, via pia.sh so the unit name lives
    // with the rest of PIA's plumbing rather than in the QML. "absent" is
    // pia.sh's own word for "the unit does not exist" -- PIA is an optional
    // extra in install.sh, and a machine that declined it should carry no PIA
    // module at all rather than one offering to start what is not installed.
    property string serviceState: ""
    readonly property bool serviceRunning: serviceState === "active"
    readonly property bool serviceAbsent: serviceState === "absent"

    property string region: ""
    property string vpnIp: ""
    property string pubIp: ""
    property string protocol: ""
    // Resolved exit region when `region` is the useless "auto".
    property string actualRegion: ""

    // What to show on the Region row: the resolved region when PIA picked one
    // for us, the configured region otherwise. Named through PiaService so the
    // row and the shortlist below it call the same place the same thing --
    // except when pia-region.sh resolved an `auto`, which gives PIA's own name
    // for it and is better than anything derived from an id.
    readonly property string regionLabel: {
        if (region === "auto")
            return actualRegion.length > 0 ? actualRegion + "  (auto)" : "Automatic";
        return region.length > 0 ? PiaService.regionName(region) : "";
    }

    Process {
        id: serviceProc
        command: ["bash", "-lc", root.script + " --service"]
        stdout: StdioCollector {
            onStreamFinished: root.serviceState = text.trim()
        }
    }

    // Starting a system unit needs a password and this session runs no polkit
    // agent, so a terminal is the only place that prompt can be answered. It
    // was the pill's right-click; PiaMenu offers it as a button, and only once
    // a poll has actually reported the daemon down.
    function startService() {
        Quickshell.execDetached(["bash", "-lc",
            "kitty --class pia-start -e " + root.script + " --start-service"]);
        startPoll.restart();
    }

    // The daemon takes a few seconds to come up and the password prompt is
    // untimed, so watch for a while rather than waiting on the 20 s tick.
    Timer {
        id: startPoll
        interval: 2000
        repeat: true
        running: false
        triggeredOnStart: true
        property int ticks: 0
        onRunningChanged: if (running) ticks = 0
        onTriggered: {
            root.refreshDetails();
            if (root.serviceRunning || ++ticks >= 45) running = false;
        }
    }

    Process {
        id: regionProc
        command: ["bash", "-lc", "~/.config/hypr/scripts/pia-region.sh"]
        stdout: StdioCollector {
            onStreamFinished: root.actualRegion = text.trim()
        }
    }

    Process {
        id: details
        command: ["bash", "-lc",
                  "piactl get region 2>/dev/null; piactl get vpnip 2>/dev/null; " +
                  "piactl get pubip 2>/dev/null; piactl get protocol 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n").map(x => x.trim());
                root.region   = l[0] !== undefined ? l[0] : "";
                root.vpnIp    = l[1] !== undefined ? l[1] : "";
                root.pubIp    = l[2] !== undefined ? l[2] : "";
                root.protocol = l[3] !== undefined ? l[3] : "";
            }
        }
    }

    function refreshDetails() {
        if (!details.running) details.running = true;
        if (!regionProc.running) regionProc.running = true;
        if (!serviceProc.running) serviceProc.running = true;
    }

    // Refresh on a slow tick, and immediately whenever the state flips or the
    // panel is about to be shown.
    Timer {
        interval: 20000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshDetails()
    }
    onConnectedChanged: { if (!connected) actualRegion = ""; refreshDetails(); }

    menu: piaMenu
    openMenu: () => {
        // The 20 s tick is far too slow for a menu you just asked for, and
        // the region list is a process nothing else runs.
        root.refreshDetails();
        PiaService.refreshRegions();
        piaMenu.open = true;
    }
    onClicked: root.menuOpen ? piaMenu.requestClose() : root.openMenu()

    PiaMenu {
        id: piaMenu
        anchorItem: root

        serviceState: root.serviceState
        connectionState: root.rawAlt
        region: root.region
        regionLabel: root.regionLabel
        vpnIp: root.vpnIp
        pubIp: root.pubIp
        protocol: root.protocol

        onStartServiceRequested: root.startService()

        onConnectRequested: root.act("--connect")
        onDisconnectRequested: root.act("--disconnect")

        onRegionRequested: id => {
            PiaService.remember(id);
            // Quoted, and quotes stripped: region ids are piactl's own and
            // contain nothing exotic, but this string is assembled into a
            // shell command.
            root.act("--set-region '" + String(id).replace(/'/g, "") + "'");
        }

        // No poll burst: opening the GUI changes nothing to report.
        onOpenClientRequested: Quickshell.execDetached(["bash", "-lc",
                                                        root.script + " --open-client"])
    }

    // Every menu action that changes something is pia.sh plus two polls. PIA
    // reports `connecting`/`disconnecting` itself, so the button has a real
    // transitional state to show -- but only once a poll has seen it, and the
    // 3 s status tick plus the 20 s detail tick are both long enough that the
    // click reads as dead.
    function act(args) {
        Quickshell.execDetached(["bash", "-lc", root.script + " " + args]);
        pollFast();
        detailPoll.restart();
    }

    // ScriptPill's pollFast only re-runs --status. The region and the two IPs
    // come from separate processes, and those are the rows that change when a
    // region is picked, so they need their own burst.
    Timer {
        id: detailPoll
        interval: 2000
        repeat: true
        running: false
        property int ticks: 0
        onRunningChanged: if (running) ticks = 0
        onTriggered: {
            root.refreshDetails();
            if (++ticks >= 10) running = false;
        }
    }
}
