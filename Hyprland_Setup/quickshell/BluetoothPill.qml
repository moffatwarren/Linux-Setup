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

    ListPopup {
        anchorItem: root
        requested: root.hovered && !btMenu.open
        title: root.adapter ? String(root.adapter.name) : "Bluetooth"
        emptyText: root.adapter && root.adapter.enabled ? "No paired devices" : "Adapter off"
        rows: Bluetooth.devices.values.map(d => ({
            text: String(d.name),
            detail: d.connected
                ? (d.batteryAvailable ? "connected  " + Math.round(d.battery * 100) + "%" : "connected")
                : (d.paired ? "paired" : "seen"),
            accent: d.connected ? Theme.green : Theme.overlay0
        }))
    }

    // Right-click opens the device picker; blueman is reachable from inside it.
    onRightClicked: btMenu.open = !btMenu.open

    BluetoothMenu {
        id: btMenu
        anchorItem: root
    }
}
