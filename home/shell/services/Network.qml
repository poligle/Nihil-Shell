pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// NetworkManager through nmcli (works with any Quickshell version).
// Port of the old wifi-menu.sh: saved networks, new ones with password,
// and WPA-Enterprise handed over to nm-connection-editor.
Singleton {
    id: root

    property bool wifiEnabled: true
    property string ssid: ""        // active Wi-Fi connection
    property int strength: 0
    property string ethernet: ""    // active wired connection
    property var networks: []       // { ssid, signal, secure, enterprise, active, saved }
    property var saved: []
    property bool scanning: false
    property string pending: ""     // SSID being connected
    property string askPassword: "" // SSID waiting for a password
    property string error: ""
    property bool watch: false      // set while the panel is open

    readonly property bool connected: ssid !== "" || ethernet !== ""

    // nmcli -t escapes ':' and '\' with a backslash.
    function fields(line: string): var {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue; }
            if (c === ":") { out.push(cur); cur = ""; continue; }
            cur += c;
        }
        out.push(cur);
        return out;
    }

    function refresh(): void {
        if (!status.running) status.running = true;
    }

    function scan(): void {
        if (!list.running) { root.scanning = true; list.running = true; }
    }

    function rescan(): void {
        root.run([Config.cmd.nmcli, "device", "wifi", "rescan"], () => root.scan());
    }

    function setWifi(on: bool): void {
        root.wifiEnabled = on;
        root.run([Config.cmd.nmcli, "radio", "wifi", on ? "on" : "off"], () => { root.refresh(); root.scan(); });
    }

    function notify(text: string): void {
        Quickshell.execDetached([Config.cmd.notifySend, "-a", "nihil", "-u", "low", "Wi-Fi", text]);
    }

    function editor(): void {
        Quickshell.execDetached([Config.cmd.nmEditor]);
    }

    function finish(net, code: int): void {
        root.pending = "";
        if (code === 0) {
            root.askPassword = "";
            root.error = "";
            root.notify(Lang.connectedTo.arg(net.ssid));
        } else if (net.secure) {
            root.askPassword = net.ssid;
            root.error = Lang.connectFailed;
        } else {
            root.error = Lang.connectFailed;
        }
        root.refresh();
        root.scan();
    }

    function connect(net, password: string): void {
        root.error = "";
        if (net.enterprise) {
            root.notify(Lang.enterpriseHint.arg(net.ssid));
            root.editor();
            return;
        }
        const nm = Config.cmd.nmcli;
        root.pending = net.ssid;
        if (net.saved && !password) {
            root.run([nm, "connection", "up", "id", net.ssid], code => root.finish(net, code));
        } else if (net.saved) {
            root.run([Config.cmd.sh, "-c", `"${nm}" connection modify id "$1" wifi-sec.psk "$2" && "${nm}" connection up id "$1"`,
                      "sh", net.ssid, password], code => root.finish(net, code));
        } else if (!net.secure) {
            root.run([nm, "device", "wifi", "connect", net.ssid], code => root.finish(net, code));
        } else if (password) {
            root.run([Config.cmd.sh, "-c", `"${nm}" device wifi connect "$1" password "$2" || { "${nm}" connection delete id "$1" >/dev/null 2>&1; exit 1; }`,
                      "sh", net.ssid, password], code => root.finish(net, code));
        } else {
            root.pending = "";
            root.askPassword = net.ssid;
        }
    }

    function disconnect(): void {
        if (root.ssid)
            root.run([Config.cmd.nmcli, "connection", "down", "id", root.ssid], () => { root.refresh(); root.scan(); });
    }

    function forget(name: string): void {
        root.run([Config.cmd.nmcli, "connection", "delete", "id", name], () => { root.refresh(); root.scan(); });
    }

    // One action at a time, with a callback on exit.
    property var afterAction: null

    function run(command: var, callback: var): void {
        if (action.running) return;
        root.afterAction = callback ?? null;
        action.command = command;
        action.running = true;
    }

    Process {
        id: action
        onExited: (code, status) => {
            const callback = root.afterAction;
            root.afterAction = null;
            if (callback) callback(code);
        }
    }

    Process {
        id: status
        command: [Config.cmd.sh, "-c",
            `"${Config.cmd.nmcli}" -t -f WIFI g; echo ---; "${Config.cmd.nmcli}" -t -f TYPE,STATE,CONNECTION d; echo ---; "${Config.cmd.nmcli}" -t -f IN-USE,SIGNAL d wifi list --rescan no`]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("---");
                if (parts.length < 3) return;
                root.wifiEnabled = parts[0].trim() === "enabled";
                let wifi = "", wired = "";
                for (const line of parts[1].trim().split("\n")) {
                    const f = root.fields(line);
                    if (f[1] !== "connected") continue;
                    if (f[0] === "wifi" && !wifi) wifi = f[2];
                    if (f[0] === "ethernet" && !wired) wired = f[2];
                }
                let level = 0;
                for (const line of parts[2].trim().split("\n")) {
                    const f = root.fields(line);
                    if (f[0] === "*") level = parseInt(f[1]) || 0;
                }
                root.ssid = wifi;
                root.ethernet = wired;
                root.strength = level;
            }
        }
    }

    Process {
        id: list
        command: [Config.cmd.sh, "-c",
            `"${Config.cmd.nmcli}" -t -f NAME,TYPE c show; echo ---; "${Config.cmd.nmcli}" -t -f IN-USE,SIGNAL,SECURITY,SSID d wifi list --rescan auto`]
        stdout: StdioCollector {
            onStreamFinished: {
                root.scanning = false;
                const parts = text.split("---");
                if (parts.length < 2) return;
                const saved = [];
                for (const line of parts[0].trim().split("\n")) {
                    const f = root.fields(line);
                    if (f[1] === "802-11-wireless") saved.push(f[0]);
                }
                const bySsid = {};
                for (const line of parts[1].trim().split("\n")) {
                    const f = root.fields(line);
                    if (f.length < 4 || !f[3]) continue;
                    const net = {
                        ssid: f[3],
                        signal: parseInt(f[1]) || 0,
                        secure: f[2] !== "" && f[2] !== "--",
                        enterprise: f[2].indexOf("802.1X") >= 0,
                        active: f[0] === "*",
                        saved: saved.indexOf(f[3]) >= 0
                    };
                    const old = bySsid[net.ssid];
                    if (!old || net.active || (!old.active && net.signal > old.signal))
                        bySsid[net.ssid] = net;
                }
                root.saved = saved;
                root.networks = Object.values(bySsid).sort((a, b) =>
                    (b.active - a.active) || (b.saved - a.saved) || (b.signal - a.signal));
            }
        }
    }

    Timer {
        interval: root.watch ? 2500 : 6000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 12000
        running: root.watch && root.wifiEnabled
        repeat: true
        triggeredOnStart: true
        onTriggered: root.scan()
    }
}
