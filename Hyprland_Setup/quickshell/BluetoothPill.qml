import Quickshell
import Quickshell.Bluetooth
import QtQuick

// waybar: "bluetooth" -- " {status}", " {device_alias}" when connected,
// with battery percentage when the device reports one.
Pill {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var connectedDevices: Bluetooth.devices.values.filter(d => d.connected)
    readonly property var device: connectedDevices.length > 0 ? connectedDevices[0] : null

    label: {
        if (!adapter || !adapter.enabled) return "\uf294 off";
        if (!device) return "\uf294 on";
        const name = String(device.name);
        return device.batteryAvailable
            ? "\uf294 " + name + " " + Math.round(device.battery * 100) + "%"
            : "\uf294 " + name;
    }
    labelColor: Theme.mauve

    // Left-click opens the device picker; blueman is reachable from inside it.
    // Right-click toggles the adapter without opening anything -- the same
    // menu/shortcut split NotificationPill uses (left opens the centre, right
    // mutes). The menu's header toggle stays as the discoverable way to do it.
    menu: btMenu
    onClicked: root.menuOpen ? btMenu.requestClose() : root.openMenu()
    onRightClicked: if (adapter) adapter.enabled = !adapter.enabled

    BluetoothMenu {
        id: btMenu
        anchorItem: root
    }
}
