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
        Quickshell.execDetached([Config.cmd.brightnessctl, "set", percent + "%"]);
    }

    // device,class,current,percent,max
    Process {
        id: reader
        command: [Config.cmd.brightnessctl, "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(",");
                if (f.length >= 5 && parseInt(f[4]) > 0) {
                    root.value = parseInt(f[2]) / parseInt(f[4]);
                    root.available = true;
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
