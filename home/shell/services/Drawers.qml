pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config

// Which drawer is open, and on which output. Only one at a time.
//   qs -c nihil ipc call drawers toggle launcher|dashboard|panel
Singleton {
    id: root

    property string current: ""     // "", "dashboard", "panel", "launcher"
    property string screen: ""
    property bool byHover: false

    function focusedScreen(): string {
        return Hyprland.focusedMonitor?.name ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "");
    }

    function isOpen(name: string, screenName: string): bool {
        return current === name && screen === screenName;
    }

    function open(name: string, screenName: string, hover: bool): void {
        screen = screenName || focusedScreen();
        byHover = hover;
        if (name === "launcher" && current !== "launcher")
            Sounds.play(Config.sounds.menu, 0.4);
        if (name === "panel")
            Notifs.markSeen();
        current = name;
    }

    function toggle(name: string, screenName: string): void {
        const target = screenName || focusedScreen();
        if (current === name && screen === target && !byHover)
            close();
        else
            open(name, target, false);
    }

    function close(): void {
        current = "";
        byHover = false;
    }

    IpcHandler {
        target: "drawers"

        function toggle(name: string): void { root.toggle(name, ""); }
        function open(name: string): void { root.open(name, "", false); }
        function close(): void { root.close(); }
    }
}
