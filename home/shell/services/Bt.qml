pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.config

Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property bool discovering: adapter?.discovering ?? false

    readonly property var all: (adapter?.devices ?? Bluetooth.devices)?.values ?? []
    readonly property var devices: all
        .filter(d => d.paired || d.connected || root.discovering)
        .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
    readonly property var connected: all.filter(d => d.connected)

    // The adapter may be soft-blocked at boot (see bluetooth-off-at-boot),
    // so unblock it before powering it on.
    function setEnabled(on: bool): void {
        if (!adapter) return;
        if (on) {
            Quickshell.execDetached([Config.cmd.rfkill, "unblock", "bluetooth"]);
            power.restart();
        } else {
            adapter.enabled = false;
        }
    }

    function scan(on: bool): void {
        if (adapter) adapter.discovering = on;
    }

    function toggleDevice(d): void {
        if (d.connected) d.disconnect();
        else if (d.paired) d.connect();
        else { d.trusted = true; d.pair(); }
    }

    Timer {
        id: power
        interval: 400
        onTriggered: if (root.adapter) root.adapter.enabled = true
    }
}
