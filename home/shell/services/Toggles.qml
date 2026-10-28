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

    // hyprsunset runs while night light is on; stopping the process restores colours.
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
