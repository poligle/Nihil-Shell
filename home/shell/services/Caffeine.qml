pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Caffeine: while it is on, the screen doesn't dim, lock or turn off and the
// laptop doesn't suspend on its own. Every frame window holds a Wayland idle
// inhibitor while it is on (Frame.qml), and hypridle honours it; closing the
// lid still suspends. It starts off with every session.
//   qs -c nihil ipc call caffeine toggle|on|off
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
