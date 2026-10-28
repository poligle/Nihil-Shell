pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// CPU, memory, temperature and network throughput from /proc and /sys.
// CPU/RAM/temperature are only sampled while the dashboard is open.
Singleton {
    id: root

    readonly property bool active: Drawers.current === "dashboard"
    property real cpu: 0            // 0..1
    property real mem: 0            // 0..1
    property real temp: 0           // degrees C
    property string iface: ""
    property real rx: 0             // bytes/s
    property real tx: 0
    property var rxHistory: []
    property var txHistory: []

    property var lastCpu: null
    property real lastRx: -1
    property real lastTx: -1
    property string tempPath: ""

    function human(bytes: real): string {
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB/s";
        if (bytes >= 1024) return Math.round(bytes / 1024) + " KB/s";
        return Math.round(bytes) + " B/s";
    }

    function push(list: var, value: real): var {
        const next = list.concat([value]);
        return next.length > 60 ? next.slice(next.length - 60) : next;
    }

    FileView { id: stat; path: "/proc/stat"; blockLoading: true }
    FileView { id: meminfo; path: "/proc/meminfo"; blockLoading: true }
    FileView { id: tempFile; path: root.tempPath; blockLoading: true }
    FileView { id: rxFile; path: root.iface ? `/sys/class/net/${root.iface}/statistics/rx_bytes` : ""; blockLoading: true }
    FileView { id: txFile; path: root.iface ? `/sys/class/net/${root.iface}/statistics/tx_bytes` : ""; blockLoading: true }

    Process {
        id: route
        command: [Config.cmd.ip, "route", "show", "default"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.match(/dev (\S+)/);
                const iface = m ? m[1] : "";
                if (iface !== root.iface) { root.lastRx = -1; root.lastTx = -1; }
                root.iface = iface;
            }
        }
    }

    Process {
        command: [Config.cmd.sh, "-c",
            "for d in /sys/class/hwmon/hwmon*; do case \"$(cat \"$d/name\")\" in k10temp|coretemp|zenpower|cpu_thermal|thinkpad) echo \"$d/temp1_input\"; exit;; esac; done; echo /sys/class/thermal/thermal_zone0/temp"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.tempPath = text.trim() }
    }

    function tick(): void {
        if (root.iface) {
            rxFile.reload();
            txFile.reload();
            const r = parseFloat(rxFile.text()), t = parseFloat(txFile.text());
            if (!isNaN(r) && !isNaN(t)) {
                if (root.lastRx >= 0) {
                    root.rx = Math.max(0, r - root.lastRx);
                    root.tx = Math.max(0, t - root.lastTx);
                }
                root.lastRx = r;
                root.lastTx = t;
            }
        } else {
            root.rx = 0;
            root.tx = 0;
        }
        root.rxHistory = root.push(root.rxHistory, root.rx);
        root.txHistory = root.push(root.txHistory, root.tx);

        if (!root.active) return;

        stat.reload();
        const cpuLine = stat.text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
        const idle = cpuLine[3] + (cpuLine[4] || 0);
        const total = cpuLine.reduce((a, b) => a + b, 0);
        if (root.lastCpu && total > root.lastCpu.total)
            root.cpu = 1 - (idle - root.lastCpu.idle) / (total - root.lastCpu.total);
        root.lastCpu = { idle: idle, total: total };

        meminfo.reload();
        const mem = {};
        for (const line of meminfo.text().split("\n")) {
            const m = line.match(/^(\w+):\s+(\d+)/);
            if (m) mem[m[1]] = parseInt(m[2]);
        }
        if (mem.MemTotal) root.mem = 1 - (mem.MemAvailable ?? mem.MemFree) / mem.MemTotal;

        if (root.tempPath) {
            tempFile.reload();
            const v = parseInt(tempFile.text());
            if (!isNaN(v)) root.temp = v / 1000;
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.tick()
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: route.running = true
    }
}
