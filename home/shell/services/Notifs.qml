pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.config

// Notification daemon (replaces dunst). Every popup also lights the frame.
// A notification with the hint x-nihil-tag replaces the earlier ones with the
// same tag, and still lights the frame (a D-Bus replace would update the old
// card silently): the battery warnings use it.
//
// Popups retire here, not in their cards: Popups.qml builds its cards again
// whenever the list changes, so a timer per card started over with every new
// notification. Each popup has a deadline instead; the one under the pointer
// waits.
Singleton {
    id: root

    property bool dnd: false
    property var popups: []
    readonly property var history: server.trackedNotifications.values.slice().reverse()

    // Milliseconds: without a timeout of its own, the longest one an app may
    // ask for, and critical ones (they stay in the panel's history).
    readonly property int defaultTimeout: 5000
    readonly property int longestTimeout: 30000
    readonly property int criticalTimeout: 15000

    property var deadlines: ({})    // notification id -> epoch ms
    property int held: -1           // id of the popup under the pointer

    function show(n): void {
        deadlines[n.id] = Date.now() + timeoutFor(n);
        popups = [n].concat(popups.filter(p => p !== n)).slice(0, 4);
    }

    function hidePopup(n): void {
        delete deadlines[n.id];
        popups = popups.filter(p => p !== n);
    }

    // The pointer on a popup holds it; leaving gives it a moment more.
    function hold(n, on: bool): void {
        if (!n) return;
        if (on) {
            held = n.id;
        } else {
            if (held === n.id) held = -1;
            deadlines[n.id] = Math.max(deadlines[n.id] ?? 0, Date.now() + 2000);
        }
    }

    function expire(): void {
        const now = Date.now();
        const keep = popups.filter(p => p.id === held || (deadlines[p.id] ?? 0) > now);
        if (keep.length === popups.length) return;
        for (const p of popups)
            if (keep.indexOf(p) < 0) delete deadlines[p.id];
        popups = keep;
    }

    // The control panel lists every notification, so opening it retires the
    // popups; critical ones stay up until their own time runs out.
    function markSeen(): void {
        popups = popups.filter(p => isCritical(p));
    }

    function clear(): void {
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
        popups = [];
        deadlines = ({});
    }

    function tagOf(n): string {
        return String(n?.hints?.["x-nihil-tag"] ?? "");
    }

    function dismissTag(tag: string, except: var): void {
        for (const n of server.trackedNotifications.values.slice())
            if (n !== except && tagOf(n) === tag) n.dismiss();
    }

    function isCritical(n): bool {
        return n.urgency === NotificationUrgency.Critical;
    }

    // Milliseconds a popup stays up. Quickshell documents expireTimeout in
    // seconds but hands on the D-Bus value as it comes, in milliseconds:
    // read as seconds, notify-send -t 5000 (hyprshot, nm-applet) stayed up
    // for 83 minutes. A value too small to be milliseconds is taken as
    // seconds, in case that changes. 0 ("never") and -1 ("you choose") get
    // the default.
    function timeoutFor(n): int {
        if (isCritical(n)) return criticalTimeout;
        const t = Number(n.expireTimeout) || 0;
        if (t <= 0) return defaultTimeout;
        return Math.max(1500, Math.min(longestTimeout, Math.round(t < 100 ? t * 1000 : t)));
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
            if (root.tagOf(n) !== "") root.dismissTag(root.tagOf(n), n);

            const critical = root.isCritical(n);
            if (root.dnd && !critical)
                return;

            root.show(n);
            Glyph.notify(critical);
            Sounds.play(critical ? Config.sounds.critical : Config.sounds.notify, critical ? 0.5 : 0.4);
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: root.popups.length > 0
        onTriggered: root.expire()
    }

    IpcHandler {
        target: "notifs"

        function clear(): void { root.clear(); }
        function toggleDnd(): void { root.dnd = !root.dnd; }
    }
}
