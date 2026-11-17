pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    property bool night: false
    property real nightLevel: 0.5
    property bool airplane: false

    readonly property int kelvin: Math.round(6000 - nightLevel * 3400)
    readonly property string nightFile: Machine.stateDir + "/night"
    // While airplane mode is on, this file lists the radios it found on (wlan, bluetooth),
    // the ones leaving it turns back on; it also tells the next start that the mode is on.
    readonly property string airplaneFile: Machine.stateDir + "/airplane"

    function setAirplane(on: bool): void {
        root.airplane = on;
        Quickshell.execDetached([Config.cmd.sh, "-c", on ? root.takeOff : root.land, "sh", Config.cmd.rfkill, root.airplaneFile]);
        settle.restart();
    }

    // $1 is rfkill and $2 the file. Turning it on twice keeps the first list; with every
    // radio already off, Wi-Fi is the one to bring back.
    readonly property string takeOff: [
        'mkdir -p "$(dirname "$2")"',
        'if [ ! -e "$2" ]; then',
        '  "$1" --noheadings --raw --output TYPE,SOFT | while read -r type soft; do [ "$soft" = unblocked ] && echo "$type"; done > "$2.new"',
        '  [ -s "$2.new" ] || echo wlan > "$2.new"',
        '  mv "$2.new" "$2"',
        'fi',
        '"$1" block all'
    ].join("\n")
    readonly property string land: [
        'if [ -e "$2" ]; then',
        '  while read -r type; do [ -n "$type" ] && "$1" unblock "$type"; done < "$2"',
        '  rm -f "$2"',
        'fi'
    ].join("\n")

    function setNightLevel(level: real): void {
        root.nightLevel = Math.max(0, Math.min(1, level));
        keep.restart();
        if (!root.night) root.night = true;
        else retune.restart();
    }

    onNightChanged: sunset.running = night

    IpcHandler {
        target: "night"

        function toggle(): void { root.night = !root.night; }
        function on(): void { root.night = true; }
        function off(): void { root.night = false; }
        function status(): string { return root.night ? "on" : "off"; }
        function level(percent: int): void { root.setNightLevel(percent / 100); }
    }

    IpcHandler {
        target: "toggles"

        function state(): string { return JSON.stringify({ caffeine: Caffeine.on, night: root.night }); }
    }

    FileView {
        path: root.nightFile
        printErrors: false
        onLoaded: {
            const level = parseFloat(text());
            if (!isNaN(level)) root.nightLevel = Math.max(0, Math.min(1, level));
        }
    }

    FileView {
        path: root.airplaneFile
        printErrors: false
        onLoaded: root.airplane = true
    }

    Timer {
        id: keep
        interval: 400
        onTriggered: Quickshell.execDetached([Config.cmd.sh, "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s\\n' \"$2\" > \"$1\"",
                                              "sh", root.nightFile, root.nightLevel.toFixed(2)])
    }

    Process {
        id: sunset
        command: [Config.cmd.hyprsunset, "-t", String(root.kelvin)]
    }

    Timer {
        id: retune
        interval: 120
        onTriggered: {
            if (tune.running) {
                restart();
                return;
            }
            tune.applied = root.kelvin;
            tune.said = "";
            tune.running = true;
        }
    }

    Process {
        id: tune
        property int applied: 0
        property string said: ""
        command: [Config.cmd.hyprctl, "hyprsunset", "temperature", String(applied)]
        stdout: SplitParser { onRead: line => tune.said += line + "\n" }
        onExited: code => {
            if (code !== 0 || /error|couldn|fail|invalid|unknown/i.test(tune.said)) {
                sunset.running = false;
                relaunch.restart();
            } else if (root.night && tune.applied !== root.kelvin) {
                retune.restart();
            }
        }
    }

    Timer {
        id: relaunch
        interval: 400
        onTriggered: sunset.running = root.night
    }

    Timer {
        id: settle
        interval: 800
        onTriggered: Network.refresh()
    }
}
