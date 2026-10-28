pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.theme

// Glyph Interface homage: light that runs along the frame.
//   startEdge: 0 top, 1 right, 2 bottom, 3 left (clockwise from that corner)
//   qs -c nihil ipc call glyph test true
Singleton {
    id: root

    signal sweep(color tint, int laps, int startEdge)

    function notify(critical: bool): void {
        root.sweep(critical ? Tokens.interrupt : Tokens.ink, critical ? 2 : 1, 1);
    }

    function charge(): void {
        root.sweep(Tokens.ink, 1, 3);
    }

    IpcHandler {
        target: "glyph"

        function test(critical: bool): void { root.notify(critical); }
    }
}
