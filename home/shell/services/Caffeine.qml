pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool on: false
    property date since: new Date()

    function toggle(): void { set(!on); }

    function set(value: bool): void {
        if (value === on) return;
        if (value) since = new Date();
        on = value;
    }

    IpcHandler {
        target: "caffeine"

        function toggle(): void { root.toggle(); }
        function on(): void { root.set(true); }
        function off(): void { root.set(false); }
        function status(): string { return root.on ? "on" : "off"; }
    }
}
