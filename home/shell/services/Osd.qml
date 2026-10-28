pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// On-screen display for volume, brightness and microphone.
// The key scripts (osd-volume, osd-brightness) do the work and report here:
//   qs -c nihil ipc call osd volume 45 false
Singleton {
    id: root

    property string kind: "volume"  // volume | brightness | mic
    property real value: 0          // 0..1
    property bool muted: false
    property bool shown: false
    property string screen: ""

    function show(kind: string, value: real, muted: bool): void {
        root.kind = kind;
        root.value = Math.max(0, Math.min(1, value));
        root.muted = muted;
        root.screen = Hyprland.focusedMonitor?.name ?? "";
        root.shown = true;
        hide.restart();
    }

    Timer {
        id: hide
        interval: 1400
        onTriggered: root.shown = false
    }

    IpcHandler {
        target: "osd"

        function volume(percent: int, muted: bool): void { root.show("volume", percent / 100, muted); }
        function brightness(percent: int): void {
            Brightness.value = percent / 100;
            root.show("brightness", percent / 100, false);
        }
        function mic(muted: bool): void { root.show("mic", muted ? 0 : 1, muted); }
    }
}
