import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

// One glyph, no text: which way the machine is on the network, and nothing
// else. The SSID, signal, IP and rates it used to spell out (waybar drew the
// essid and its strength on wifi, the address on ethernet) are the status block
// at the top of WifiMenu -- the bar itself only has to answer "am I on, and
// over what", and the numbers are one click away.
//
// This file still works all of that out; the menu only draws it. That is why
// the throughput sampler and the two IP lookups stay here rather than moving
// into WifiMenu: the rate counters have to be sampled continuously to have a
// delta at all, and a menu that is shut most of the time cannot do that.
//
// Quickshell's NetworkDevice.address is the MAC, not the IP, and no IP is
// exposed anywhere on the device or its network object -- so the address is
// read from `ip` instead. It re-reads when the active device changes rather
// than on a poll, with a slow backstop for lease renewals.
Pill {
    id: root

    readonly property var devices: Networking.devices.values
    readonly property var active: {
        const up = devices.filter(d => d.connected);
        if (up.length === 0) return null;
        // Prefer a wired link when both are up, matching typical desktop use.
        const wired = up.filter(d => d.type === DeviceType.Wired);
        return wired.length > 0 ? wired[0] : up[0];
    }

    // Whether this machine has wifi hardware at all, connected or not -- it is
    // what separates a disconnected laptop from a disconnected desktop, and so
    // which "nothing is up" glyph to draw. The device is listed while it is
    // down (verified: wlan0 is in Networking.devices while disconnected), so
    // there is nothing to ask NetworkManager separately.
    readonly property bool wifiCapable: devices.some(d => d.type === DeviceType.Wifi)

    // --- the network this machine is actually on ----------------------------
    // NetworkDevice exposes no `network` property -- only `networks`, the list
    // of everything in range (verified against quickshell-network.qmltypes:
    // type, name, networks, address, connected, state, nmManaged, autoconnect,
    // and nothing else). The obvious answer is therefore the connected member
    // of `networks`, and it does not work, because **`networks` is populated
    // only while `scannerEnabled` is true.** Verified on this machine: with the
    // scanner off it is empty even though NetworkManager itself is holding 41
    // access points (`nmcli device wifi list --rescan no`); turning the scanner
    // on filled it inside 1.5 s and turning it off emptied it again. Since
    // WifiMenu stopped scanning on open, nothing enables the scanner unless the
    // Scan button is pressed -- so a `networks`-derived SSID and signal would
    // simply vanish from the status block, which is the one place they are now
    // shown.
    //
    // So they are read from NetworkManager's own cache instead, the same way
    // the IP already is. `--rescan no` is what makes that a read and not a
    // scan: it returns what NM last saw and never puts the radio to work.
    property string wifiSsid: ""
    // 0..1, to match the scale WifiMenu's meter draws its rows on. nmcli
    // reports 0-100, hence the divide; -1 means "not on wifi".
    property real wifiSignal: -1

    // `nmcli -t` separates fields with ":" and escapes any colon *inside* a
    // value as "\:", so the split has to respect the backslash -- an SSID with
    // one in it would otherwise take the signal column with it. Written as a
    // scan rather than `split(/(?<!\\):/)` because **QML's JS engine does not
    // support lookbehind and does not say so**: verified on this Qt, that regex
    // throws nothing and simply never matches, so `split` hands back the whole
    // line as one field and the signal parses as NaN. Unescapes as it goes.
    function splitEscaped(line) {
        const out = [];
        var cur = "";
        for (var i = 0; i < line.length; i++) {
            const c = line.charAt(i);
            if (c === "\\" && i + 1 < line.length) { cur += line.charAt(++i); continue; }
            if (c === ":") { out.push(cur); cur = ""; continue; }
            cur += c;
        }
        out.push(cur);
        return out;
    }

    function refreshWifiInfo() {
        if (!active || active.type !== DeviceType.Wifi) {
            wifiSsid = "";
            wifiSignal = -1;
            return;
        }
        if (!wifiInfoProc.running) wifiInfoProc.running = true;
    }

    Process {
        id: wifiInfoProc
        command: ["bash", "-lc",
                  "nmcli -t -f IN-USE,SIGNAL,SSID device wifi list --rescan no 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].charAt(0) !== "*") continue;
                    const f = root.splitEscaped(lines[i]);
                    const pct = parseInt(f[1], 10);
                    root.wifiSignal = isNaN(pct) ? -1 : Math.max(0, Math.min(1, pct / 100));
                    // Everything after the signal column, since an SSID may
                    // contain a colon of its own.
                    root.wifiSsid = f.slice(2).join(":");
                    return;
                }
                // Connected but NM lists no in-use AP: keep nothing rather than
                // the previous network's name.
                root.wifiSsid = "";
                root.wifiSignal = -1;
            }
        }
    }

    property string ipAddress: ""

    // --- throughput ---------------------------------------------------------
    // Quickshell's Networking exposes no byte counters, so rates come from the
    // kernel's own totals in sysfs. FileView reads them without spawning a
    // process, which matters for a once-a-second sample.
    property real rxRate: 0     // bytes/sec
    property real txRate: 0
    property real lastRx: -1
    property real lastTx: -1

    readonly property string ifacePath: active ? "/sys/class/net/" + active.name + "/statistics/" : ""

    FileView { id: rxFile; path: root.ifacePath.length > 0 ? root.ifacePath + "rx_bytes" : ""; blockLoading: true }
    FileView { id: txFile; path: root.ifacePath.length > 0 ? root.ifacePath + "tx_bytes" : ""; blockLoading: true }

    Timer {
        interval: 1000
        running: root.ifacePath.length > 0
        repeat: true
        onTriggered: {
            rxFile.reload();
            txFile.reload();
            const r = parseFloat(rxFile.text());
            const t = parseFloat(txFile.text());
            if (isNaN(r) || isNaN(t)) return;
            // First sample after start or an interface change has no baseline.
            if (root.lastRx >= 0 && r >= root.lastRx) root.rxRate = r - root.lastRx;
            if (root.lastTx >= 0 && t >= root.lastTx) root.txRate = t - root.lastTx;
            root.lastRx = r;
            root.lastTx = t;
        }
    }

    function refreshIp() {
        if (!active) {
            ipAddress = "";
            return;
        }
        ipProc.command = ["bash", "-lc", "ip -4 -br addr show " + active.name + " | awk '{print $3}'"];
        ipProc.running = true;
    }

    onActiveChanged: {
        refreshIp();
        refreshWifiInfo();
        // Not merely stale but unknown: the old link's address is not this
        // link's, and a wrong address is worse than a missing row.
        publicIp = "";
        publicIpStale = true;
        lastRx = -1;
        lastTx = -1;
        rxRate = 0;
        txRate = 0;
    }
    Component.onCompleted: { refreshIp(); refreshWifiInfo(); }

    Process {
        id: ipProc
        stdout: StdioCollector {
            onStreamFinished: root.ipAddress = text.trim()
        }
    }

    // --- public IP ----------------------------------------------------------
    // Unlike the interface address this one has to be asked of somebody else's
    // server, so it is fetched when the menu opens rather than polled -- the
    // menu is its only consumer, and an idle bar should ask nobody anything.
    // public-ip.sh caches for ten minutes, so a run of openings costs one `cat`
    // apiece. It was on hover, which is the same rule against the panel this
    // block replaced.
    property string publicIp: ""
    // A link change makes the cached address the one answer that is certainly
    // wrong, so the next fetch has to go past the cache. It starts set because
    // a cache surviving from a previous session is in exactly that position.
    property bool publicIpStale: true

    function refreshPublicIp() {
        if (pubIpProc.running) return;
        pubIpProc.command = ["bash", "-lc",
            "~/.config/hypr/scripts/public-ip.sh" + (publicIpStale ? " --force" : "")];
        pubIpProc.running = true;
    }

    Process {
        id: pubIpProc
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim();
                // The script prints nothing rather than guessing, so an empty
                // answer means "ask again later", not "you have no address".
                if (v.length === 0) return;
                root.publicIp = v;
                root.publicIpStale = false;
            }
        }
    }


    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            if (!ipProc.running) root.refreshIp();
            root.refreshWifiInfo();
        }
    }

    // Material Design Icons from the nerd font, as surrogate pairs (see
    // CLAUDE.md) -- the family AudioPill draws from, and the one with a
    // slashed counterpart for each of these states. The shape says which
    // medium, the slash says whether it is up, and `labelColor` still turns
    // the whole thing red when nothing is connected, as it did the old text.
    label: {
        if (active)
            return active.type === DeviceType.Wifi
                ? "\udb81\udda9"      // wifi
                : "\udb80\ude00";     // ethernet
        return wifiCapable
            ? "\udb81\uddaa"          // wifi-off
            : "\udb80\ude02";         // ethernet-cable-off
    }
    labelColor: active ? Theme.text : Theme.red

    // Left-click opens the wifi picker; nmtui is still reachable from inside it.
    // Left rather than right to match BluetoothPill and NotificationPill, which
    // both put their menu on the primary button. The right button is unbound
    // here -- the wifi radio toggle lives in the menu header, unlike the
    // bluetooth adapter, which has it on both.
    menu: wifiMenu
    // Defined here rather than in onClicked so the hover hand-off takes exactly
    // the same path a click does -- a menu arrived at by hover must not show a
    // stale IP and a stale signal reading.
    openMenu: () => {
        root.refreshPublicIp();
        // The status block is about to be looked at, and the 30 s tick is
        // too slow for a signal reading you just asked for.
        root.refreshWifiInfo();
        wifiMenu.open = true;
    }
    onClicked: root.menuOpen ? wifiMenu.requestClose() : root.openMenu()

    WifiMenu {
        id: wifiMenu
        anchorItem: root

        hasActive: root.active !== null
        activeIsWifi: root.active !== null && root.active.type === DeviceType.Wifi
        deviceName: root.active ? String(root.active.name) : ""
        ssid: root.wifiSsid
        signalStrength: root.wifiSignal
        ipAddress: root.ipAddress
        publicIp: root.publicIp
        macAddress: root.active ? String(root.active.address) : ""
        rxRate: root.rxRate
        txRate: root.txRate
    }
}
