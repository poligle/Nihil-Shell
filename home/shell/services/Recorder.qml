pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Screen recording and screenshots from the panel (drawers/Panel.qml) and the
// keys (home/hyprland.nix). nihil-record (home/scripts.nix) does the
// recording and says here when it starts and stops; while it records, the
// bar's privacy LED is lit, as for the microphone (frame/Bar.qml).
//   qs -c nihil ipc call recorder status
Singleton {
    id: root

    property bool recording: false

    // From the panel the screen is recorded whole, and the screenshot is of an
    // area; both wait for the drawer to close, or it would be in the picture.
    function toggle(): void {
        if (root.recording)
            Quickshell.execDetached([Config.cmd.record, "stop"]);
        else
            later.run([Config.cmd.record, "start", "screen"]);
    }

    function shot(): void {
        later.run([Config.cmd.shot, "region"]);
    }

    IpcHandler {
        target: "recorder"

        function started(): void { root.recording = true; }
        function stopped(): void { root.recording = false; }
        function status(): string { return root.recording ? "on" : "off"; }
    }

    Timer {
        id: later

        property var command: []

        function run(command: var): void {
            later.command = command;
            later.restart();
        }

        interval: 350
        onTriggered: Quickshell.execDetached(later.command)
    }

    // A shell that starts while something records (it was restarted) asks.
    Process {
        running: true
        command: [Config.cmd.record, "status"]
        stdout: StdioCollector {
            onStreamFinished: root.recording = text.trim() === "on"
        }
    }
}
