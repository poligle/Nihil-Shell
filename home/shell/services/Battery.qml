pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.UPower

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

    // Don't light the frame for the state we find at login, only for plug-ins.
    property bool armed: false

    Timer {
        interval: 4000
        running: true
        onTriggered: root.armed = true
    }

    onChargingChanged: {
        if (charging && armed) Glyph.charge();
    }
}
