pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.config

// Notification daemon (replaces dunst). Every popup also lights the frame.
Singleton {
    id: root

    property bool dnd: false
    property var popups: []
    readonly property var history: server.trackedNotifications.values.slice().reverse()

    function hidePopup(n): void {
        popups = popups.filter(p => p !== n);
    }

    // The control panel lists every notification, so opening it retires the
    // popups; critical ones stay up until they are dismissed.
    function markSeen(): void {
        popups = popups.filter(p => isCritical(p));
    }

    function clear(): void {
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
        popups = [];
    }

    function isCritical(n): bool {
        return n.urgency === NotificationUrgency.Critical;
    }

    // Milliseconds a popup stays up. Quickshell gives expireTimeout in seconds;
    // without one, 5 s. Critical notifications stay until dismissed.
    function timeoutFor(n): int {
        if (isCritical(n)) return 0;
        const t = n.expireTimeout;
        return t > 0 ? Math.round(t * 1000) : 5000;
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: true
        bodyMarkupSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            n.closed.connect(() => root.hidePopup(n));

            const critical = root.isCritical(n);
            if (root.dnd && !critical)
                return;

            root.popups = [n].concat(root.popups.filter(p => p !== n)).slice(0, 4);
            Glyph.notify(critical);
            Sounds.play(critical ? Config.sounds.critical : Config.sounds.notify, critical ? 0.5 : 0.4);
        }
    }

    IpcHandler {
        target: "notifs"

        function clear(): void { root.clear(); }
        function toggleDnd(): void { root.dnd = !root.dnd; }
    }
}
