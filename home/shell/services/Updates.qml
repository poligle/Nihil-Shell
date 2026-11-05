pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Whether there is a newer NIHIL: how many commits GitHub has past the one
// this machine pins, and which (nihil check, modules/nihil-cli.nix). Checked
// a minute after the session starts, every 6 hours, and when the panel's
// update button is opened if the last check is half an hour old. Updating
// is Machine.update: it brings NIHIL and what it pins, NixOS and its
// packages with it.
Singleton {
    id: root

    // "", "checking", "current", "behind", "offline" or "unknown" (not from GitHub)
    property string state: ""
    property int behind: 0
    property var commits: []        // { sha, subject }, newest first, up to 20
    property string pinned: ""
    property string dev: ""         // nihil dev's checkout, while there is one
    property real checkedAt: 0

    // In a few words, for the panel: what the pointer on its button shows.
    readonly property string summary: state === "behind" ? (behind === 1 ? Lang.updBehindOne : Lang.updBehind.arg(behind))
        : state === "current" ? Lang.updCurrent.arg(pinned)
        : state === "offline" ? Lang.updOffline
        : state === "unknown" ? Lang.updUnknown
        : Lang.updChecking

    function check(): void {
        if (checker.running)
            return;
        if (state === "")
            state = "checking";
        checker.running = true;
    }

    function maybeCheck(): void {
        if (Date.now() - checkedAt > 30 * 60 * 1000)
            check();
    }

    Timer {
        interval: 60 * 1000
        running: true
        onTriggered: root.check()
    }

    Timer {
        interval: 6 * 3600 * 1000
        running: true
        repeat: true
        onTriggered: root.check()
    }

    Process {
        id: checker
        command: [Config.cmd.nihil, "check", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const found = JSON.parse(text);
                    root.state = found.state ?? "unknown";
                    root.behind = found.behind ?? 0;
                    root.commits = found.commits ?? [];
                    root.pinned = found.pinned ?? "";
                    root.dev = found.dev ?? "";
                } catch (error) {
                    root.state = "offline";
                }
                root.checkedAt = Date.now();
            }
        }
    }
}
