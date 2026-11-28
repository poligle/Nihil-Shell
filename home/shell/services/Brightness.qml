pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    property real value: 0
    property bool available: false

    function refresh(): void {
        if (!reader.running) reader.running = true;
    }

    function set(v: real): void {
        const percent = Math.round(Math.max(0.01, Math.min(1, v)) * 100);
        value = percent / 100;
        Quickshell.execDetached([Config.cmd.brightnessctl, "-c", "backlight", "set", percent + "%"]);
    }

    // Backlights alone: with none, brightnessctl takes a keyboard LED, Caps Lock's or Num Lock's,
    // and the row would move it. A line each, as there may be more than one: the first is shown.
    Process {
        id: reader
        command: [Config.cmd.brightnessctl, "-m", "-c", "backlight"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\n")[0].split(",");
                root.available = f.length >= 5 && parseInt(f[4]) > 0;
                if (root.available)
                    root.value = parseInt(f[2]) / parseInt(f[4]);
            }
        }
    }

    // Read at start and as the panel opens, not every few seconds: the brightness keys tell the
    // OSD what they set (osd brightness), and a computer with no backlight would be asked forever.
    Component.onCompleted: root.refresh()
}
