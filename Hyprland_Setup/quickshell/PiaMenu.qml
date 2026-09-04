import Quickshell
import QtQuick
import QtQuick.Layouts

// Left-click dropdown on the PIA module. It carries everything the module used
// to put in a hover panel -- the daemon, the connection, the region, the two
// IPs and the protocol -- plus the three things a panel could not have: the
// button that starts the daemon (which was the pill's right-click), the
// Connect/Disconnect button (its double-click), and a shortlist of regions.
//
// The shortlist is `auto` plus five, from PiaService. PIA publishes 190
// regions; a menu is not the place to pick from those, and the PIA client in
// the footer already is.
//
// It owns no state and runs no commands: PiaPill polls pia.sh, knows how to
// make the state settle quickly after a click, and is the only thing that runs
// anything. The menu reports and signals back.
MenuPopup {
    id: root

    // pia.sh's own words. `serviceAbsent` means the unit does not exist -- but
    // the pill hides itself entirely in that case, so this menu never opens on
    // a machine without PIA.
    property string serviceState: ""
    readonly property bool serviceRunning: serviceState === "active"
    // Not merely "not running": before the first poll lands, nothing is known,
    // and offering to start a daemon that may already be up is a guess.
    readonly property bool serviceDown: serviceState.length > 0 && !serviceRunning
                                        && serviceState !== "absent"

    // ScriptPill's `alt`: connected / connecting / disconnecting / disconnected
    // / error / unknown.
    property string connectionState: ""
    readonly property bool connected: connectionState === "connected"
    // A click has landed and the tunnel is moving. PIA reports this itself, so
    // unlike TailscalePill there is no local flag to hold and expire.
    readonly property bool busy: connectionState === "connecting"
                                 || connectionState === "disconnecting"

    // The selected region id ("auto", or e.g. "us-seattle"), what it resolved
    // to when it is "auto", and the rest of the detail rows.
    property string region: ""
    property string regionLabel: ""
    property string vpnIp: ""
    property string pubIp: ""
    property string protocol: ""

    signal connectRequested()
    signal disconnectRequested()
    signal startServiceRequested()
    signal regionRequested(string id)
    signal openClientRequested()

    implicitWidth: 290
    implicitHeight: body.implicitHeight + 20

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Theme.popupPad
        spacing: 5

        // --- header, and the primary action -----------------------------
        // Connect/Disconnect is always this button, and it is inert while
        // the daemon is down rather than being replaced by Start service --
        // a button that changes what it does under the pointer is worse
        // than one that is visibly unavailable, and the two actions are not
        // alternatives: starting the daemon is what makes connecting
        // possible, so both are on screen at once when both are relevant.
        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "PIA VPN"
                color: Theme.lavender
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitWidth: actionLabel.implicitWidth + 16
                implicitHeight: 20
                radius: 6
                color: actionMouse.containsMouse ? Theme.surface1 : Theme.surface0
                border.width: 1
                border.color: Theme.surface2

                Text {
                    id: actionLabel
                    anchors.centerIn: parent
                    text: root.connectionState === "connecting" ? "Connecting\u2026"
                        : root.connectionState === "disconnecting" ? "Disconnecting\u2026"
                        : root.connected ? "Disconnect" : "Connect"
                    color: root.serviceDown ? Theme.overlay0
                         : root.busy ? Theme.yellow
                         : root.connected ? Theme.red : Theme.green
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                MouseArea {
                    id: actionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // Nothing to connect with while the daemon is down, and
                    // a second click mid-transition would queue a connect
                    // behind a disconnect; the label already says to wait.
                    enabled: !root.busy && !root.serviceDown
                    onClicked: {
                        if (root.connected) root.disconnectRequested();
                        else root.connectRequested();
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface1 }

        // --- daemon down: that is the whole menu -------------------------
        // Every row below reads piactl, which answers nothing without the
        // daemon, so showing them would be showing blanks.
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.serviceDown
            spacing: 3

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Service"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "Not running"
                    color: Theme.red
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: 22
                radius: 6
                color: startMouse.containsMouse ? Theme.surface1 : Theme.surface0
                border.width: 1
                border.color: Theme.surface2

                Text {
                    anchors.centerIn: parent
                    text: "Start service"
                    color: Theme.peach
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }

                MouseArea {
                    id: startMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.startServiceRequested()
                }
            }

            // Starting a system unit needs a password and this session runs
            // no polkit agent, so the button opens a terminal to ask in.
            // Worth saying, since a terminal appearing out of a bar menu is
            // otherwise a surprise.
            Text {
                Layout.fillWidth: true
                text: "Opens a terminal for the password."
                wrapMode: Text.Wrap
                color: Theme.overlay0
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }

        // --- the connection ---------------------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            visible: !root.serviceDown
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Text {
                    text: "Status"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.connected ? "Connected"
                        : root.busy ? root.connectionState
                        : root.connectionState === "error" ? "Daemon not responding"
                        : "Not connected"
                    color: root.connected ? Theme.green
                         : root.busy ? Theme.yellow : Theme.red
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }

            Repeater {
                // Built here rather than as five conditional rows: piactl
                // answers "Unknown" for the IPs while disconnected, and a
                // row saying Unknown is worse than no row.
                model: {
                    const out = [];
                    if (root.regionLabel.length > 0)
                        out.push({ text: "Region", detail: root.regionLabel,
                                   accent: Theme.subtext0 });
                    if (root.connected && root.pubIp.length > 0 && root.pubIp !== "Unknown")
                        out.push({ text: "Exit IP", detail: root.pubIp,
                                   accent: Theme.sapphire });
                    if (!root.connected && root.pubIp.length > 0 && root.pubIp !== "Unknown")
                        out.push({ text: "Public IP", detail: root.pubIp,
                                   accent: Theme.subtext0 });
                    if (root.vpnIp.length > 0 && root.vpnIp !== "Unknown")
                        out.push({ text: "VPN IP", detail: root.vpnIp,
                                   accent: Theme.subtext0 });
                    if (root.protocol.length > 0)
                        out.push({ text: "Protocol", detail: root.protocol,
                                   accent: Theme.subtext0 });
                    return out;
                }

                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 16

                    Text {
                        text: modelData.text
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        Layout.maximumWidth: 170
                        text: modelData.detail
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                        color: modelData.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }
            }
        }

        // --- the shortlist ----------------------------------------------
        Text {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: !root.serviceDown
            text: "Connect to"
            color: Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
        }

        Repeater {
            // "auto" is pinned at the top: it is the only entry that is not
            // a place, and letting it fall off a most-recently-used list
            // would take away the way back to letting PIA choose.
            model: root.serviceDown ? [] : ["auto"].concat(PiaService.shortlist)

            Rectangle {
                id: regionRow

                required property var modelData
                readonly property bool current: root.region === regionRow.modelData

                Layout.fillWidth: true
                implicitHeight: 24
                radius: 6
                color: regionMouse.containsMouse ? Theme.surface0 : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    spacing: 8

                    // A filled dot for the selected region, an empty ring
                    // for the rest -- the radio-button shape AudioMenu uses
                    // for its inputs, and for the same reason: exactly one
                    // of these is in force at a time.
                    Rectangle {
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: 4
                        antialiasing: true
                        color: regionRow.current
                               ? (root.connected ? Theme.green : Theme.text)
                               : "transparent"
                        border.width: regionRow.current ? 0 : 1
                        border.color: Theme.surface2
                    }

                    Text {
                        Layout.fillWidth: true
                        text: PiaService.regionName(regionRow.modelData)
                        elide: Text.ElideRight
                        color: regionRow.current ? Theme.text : Theme.subtext0
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }

                MouseArea {
                    id: regionMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.regionRequested(regionRow.modelData)
                }
            }
        }

        // --- footer ------------------------------------------------------
        // The full region list, the settings and the account all live in
        // the GUI, which is also what `piactl connect` needs running unless
        // background mode is enabled. It sits here for the same reason
        // pavucontrol, blueman and nmtui sit at the foot of their menus.
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.surface1 }

        Text {
            text: "Open PIA client\u2026"
            color: clientMouse.containsMouse ? Theme.lavender : Theme.subtext0
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2

            MouseArea {
                id: clientMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.openClientRequested();
                    root.requestClose();
                }
            }
        }
    }
}
