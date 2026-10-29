pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme

// Glyph Interface homage: light that runs along the frame (GlyphLight.qml).
//   sweep: startEdge 0 top, 1 right, 2 bottom, 3 left (clockwise from that corner)
//   rise:  from the middle of the bottom edge up both sides (the charger)
//   qs -c nihil ipc call glyph test true      qs -c nihil ipc call glyph charge
Singleton {
    id: root

    signal sweep(color tint, int laps, int startEdge)
    signal rise(color tint)

    function notify(critical: bool): void {
        root.sweep(critical ? Tokens.interrupt : Tokens.ink, critical ? 2 : 1, 1);
    }

    function charge(): void {
        root.rise(Tokens.ink);
    }

    IpcHandler {
        target: "glyph"

        function test(critical: bool): void { root.notify(critical); }
        function charge(): void { root.charge(); }
    }
}
