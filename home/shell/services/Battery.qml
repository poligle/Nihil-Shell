pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.config

// The laptop battery, through UPower. Plugging the charger lights the frame
// from the bottom; running low on battery warns in red at 15, 10 and 5 %.
//   qs -c nihil ipc call battery warn 10      (shows the warning, to see it)
Singleton {
    id: root

    readonly property var device: UPower.displayDevice
    readonly property bool present: device?.isLaptopBattery ?? false
    readonly property real level: {
        const p = device?.percentage ?? 0;
        return p > 1 ? p / 100 : p;
    }
    readonly property bool charging: device?.state === UPowerDeviceState.Charging
                                     || device?.state === UPowerDeviceState.PendingCharge
    readonly property bool full: device?.state === UPowerDeviceState.FullyCharged
    readonly property bool low: present && !charging && level <= 0.15

    // Warnings: each one a critical notification (red LED, the frame lit twice
    // in red). `band` is how many thresholds the level is at or under; a new
    // warning only comes for a deeper band than the last one, so a level that
    // wavers around a threshold warns once. Charging lowers it back.
    readonly property var thresholds: [0.15, 0.10, 0.05]
    readonly property int band: thresholds.filter(t => level <= t + 0.0001).length
    property int warned: 0

    // Don't light the frame for the state we find at login, only for plug-ins;
    // and give UPower a moment before trusting the level.
    property bool armed: false

    Timer {
        interval: 4000
        running: true
        onTriggered: {
            root.armed = true;
            root.check();
        }
    }

    onChargingChanged: {
        if (charging && armed) Glyph.charge();
        check();
    }
    onBandChanged: check()
    onFullChanged: check()
    onPresentChanged: check()

    function check(): void {
        if (!armed || !present) return;
        if (charging || full) {
            // Plugged in: the warning has done its job.
            if (warned > 0) Notifs.dismissTag("battery");
            warned = Math.min(warned, band);
            return;
        }
        if (band > warned) {
            warned = band;
            warn(Math.round(level * 100), band === thresholds.length);
        }
    }

    // A new warning replaces the previous one (Notifs.qml, by its tag).
    function warn(percent: int, last: bool): void {
        Quickshell.execDetached([Config.cmd.notifySend, "--urgency=critical", "--app-name=" + Lang.batteryApp,
                                 "--hint=string:x-nihil-tag:battery",
                                 Lang.batteryLow.arg(percent), last ? Lang.batteryLowLast : Lang.batteryLowPlug]);
    }

    IpcHandler {
        target: "battery"

        function warn(percent: int): void { root.warn(percent, percent <= 5); }
    }
}
