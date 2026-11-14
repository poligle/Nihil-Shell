pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    property bool night: false
    property bool airplane: false

    function setAirplane(on: bool): void {
        root.airplane = on;
        Quickshell.execDetached([Config.cmd.rfkill, on ? "block" : "unblock", "all"]);
        settle.restart();
    }

    IpcHandler {
        target: "night"

        function toggle(): void { root.night = !root.night; }
        function on(): void { root.night = true; }
        function off(): void { root.night = false; }
        function status(): string { return root.night ? "on" : "off"; }
    }

    IpcHandler {
        target: "toggles"

        function state(): string { return JSON.stringify({ caffeine: Caffeine.on, night: root.night }); }
    }

    Process {
        command: [Config.cmd.hyprsunset, "-t", "4300"]
        running: root.night
    }

    Timer {
        id: settle
        interval: 800
        onTriggered: Network.refresh()
    }
}
