pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.config

Singleton {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    // BlueZ's own word on it: Quickshell keeps the value it asked for even
    // when BlueZ refuses it. While it is turning on, on.
    readonly property bool enabled: turningOn || adapter?.state === BluetoothAdapterState.Enabled
    readonly property bool discovering: adapter?.discovering ?? false

    readonly property var all: (adapter?.devices ?? Bluetooth.devices)?.values ?? []
    readonly property var devices: all
        .filter(d => d.paired || d.connected || root.discovering)
        .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
    readonly property var connected: all.filter(d => d.connected)

    property bool turningOn: false
    property int waited: 0

    // On: unblocked first (a key, airplane mode, or a shutdown with it
    // blocked; systemd's uaccess hands the session /dev/rfkill), and
    // bluetoothd powers it on by itself once it is. Meanwhile it is asked
    // again while it is off, and one still coming up, its firmware loading,
    // is waited for up to 15 s. If it does not come on the journal says why
    // (journalctl --user -u nihil-shell | grep bluetooth).
    function setEnabled(on: bool): void {
        power.stop();
        root.turningOn = on;
        if (on) {
            root.waited = 0;
            unblock.running = true;
        } else if (root.adapter && (root.adapter.state === BluetoothAdapterState.Enabled || root.adapter.state === BluetoothAdapterState.Enabling)) {
            root.write(root.adapter, false);
        }
    }

    // Quickshell skips a write equal to the value it holds, which can be one
    // BlueZ refused: then the other one goes first.
    function write(adapter: var, on: bool): void {
        if (adapter.enabled === on) adapter.enabled = !on;
        adapter.enabled = on;
    }

    function scan(on: bool): void {
        if (adapter) adapter.discovering = on;
    }

    function toggleDevice(d): void {
        if (d.connected) d.disconnect();
        else if (d.paired) d.connect();
        else { d.trusted = true; d.pair(); }
    }

    Process {
        id: unblock
        command: [Config.cmd.rfkill, "unblock", "bluetooth"]
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "") console.warn("nihil: bluetooth: rfkill:", text.trim())
        }
        onExited: if (root.turningOn) power.start()
    }

    Timer {
        id: power
        interval: 500
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const adapter = root.adapter;
            if (adapter?.state === BluetoothAdapterState.Enabled) {
                root.turningOn = false;
                stop();
            } else if (++root.waited > 30) {
                console.warn("nihil: bluetooth: did not come on:", adapter ? BluetoothAdapterState.toString(adapter.state) : "no adapter");
                root.turningOn = false;
                stop();
            } else if (adapter?.state === BluetoothAdapterState.Disabled) {
                root.write(adapter, true);
            }
        }
    }
}
