pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Where the windows are, for the smoked glass that shows them behind it
// (components/Backdrop.qml). Hyprland says when one opens, closes, floats, goes
// fullscreen or to another workspace, but nothing while one is dragged: so
// their places are asked for a few times a second while the glass is on, five
// times while some glass shows windows (`live`), and twenty while those are
// moving (a window dragged under the frame stays where it is seen), until they
// have been still for a moment. With the glass off, never.
Singleton {
    id: root

    readonly property bool on: Machine.glass
    // Backdrops showing windows now (they count themselves).
    property int live: 0
    // The windows' places last time, and whether they have moved lately.
    property string seen: ""
    property double movedAt: 0
    property bool moving: false

    function places(): string {
        return Hyprland.toplevels.values.map(client => {
            const ipc = client.lastIpcObject;
            return ipc && ipc.at && ipc.size ? ipc.at.join(",") + "," + ipc.size.join(",") : "";
        }).join(";");
    }

    function refresh(): void {
        Hyprland.refreshToplevels();
    }

    // A window's place on its screen, logical px (empty when it isn't shown).
    function place(client: var, monitor: var): rect {
        const ipc = client?.lastIpcObject;
        if (!ipc || !ipc.at || !ipc.size || !monitor || ipc.hidden || ipc.mapped === false)
            return Qt.rect(0, 0, 0, 0);
        return Qt.rect(ipc.at[0] - monitor.x, ipc.at[1] - monitor.y, ipc.size[0], ipc.size[1]);
    }

    // The special workspace out on a screen, if any.
    function specialOf(monitor: var): var {
        const id = monitor?.lastIpcObject?.specialWorkspace?.id ?? 0;
        return id !== 0 ? Hyprland.workspaces.values.find(w => w.id === id) ?? null : null;
    }

    // Whether a window of the screen's workspaces reaches into its frame (the
    // bar, the edges), for a screen of `w` by `h` logical px. Not a fullscreen
    // one (Hyprland's 2): it covers the frame, and capturing it (a game, a
    // film) would only cost.
    function underFrame(monitor: var, inset: real, edge: real, w: real, h: real): bool {
        const clients = [monitor?.activeWorkspace, root.specialOf(monitor)].filter(ws => ws)
            .reduce((all, ws) => all.concat(Array.from(ws.toplevels.values)), []);
        if (clients.some(client => (client.lastIpcObject?.fullscreen ?? 0) >= 2))
            return false;
        return clients.some(client => {
            const r = root.place(client, monitor);
            return r.width > 0 && (r.x < inset - 1 || r.y < edge - 1 || r.x + r.width > w - edge + 1 || r.y + r.height > h - edge + 1);
        });
    }

    Timer {
        interval: root.live > 0 ? (root.moving ? 50 : 200) : 400
        running: root.on && Hyprland.toplevels.values.length > 0
        repeat: true
        onTriggered: {
            const now = root.places();
            if (now !== root.seen) {
                root.seen = now;
                root.movedAt = Date.now();
            }
            root.moving = Date.now() - root.movedAt < 1500;
            root.refresh();
        }
    }

    Connections {
        target: Hyprland
        enabled: root.on

        function onRawEvent(event: var): void {
            switch (event.name) {
            case "activespecial":
                Hyprland.refreshMonitors();
                root.refresh();
                break;
            case "openwindow":
            case "closewindow":
            case "movewindowv2":
            case "changefloatingmode":
            case "fullscreen":
            case "workspacev2":
                root.refresh();
                break;
            }
        }
    }
}
