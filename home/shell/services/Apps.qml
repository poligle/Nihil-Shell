pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Desktop entries and a small fuzzy search for the launcher. The phone's
// deck (home/deck) opens the same ones, and web pages, through here, and
// locks the screen as the launcher's action does:
//   nihil-ipc apps list | launch <id> | url <https://…>
//   nihil-ipc session lock
Singleton {
    id: root

    // Case-insensitive, so the order is the same whatever the session locale.
    readonly property var all: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()))

    function score(e, q: string): int {
        const name = e.name.toLowerCase();
        if (name === q) return 1000;
        if (name.startsWith(q)) return 800 - name.length;
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 600 - name.length;
        if (name.indexOf(q) >= 0) return 400 - name.indexOf(q);
        const extra = [e.genericName ?? "", e.comment ?? "", ...(e.keywords ?? [])].join(" ").toLowerCase();
        if (extra.indexOf(q) >= 0) return 200;
        // subsequence: every character of q appears in order
        let i = 0;
        for (const c of name) if (c === q[i]) i++;
        return i === q.length ? 100 - name.length : -1;
    }

    function search(query: string): var {
        const q = query.trim().toLowerCase();
        if (!q) return root.all;
        return root.all
            .map(e => ({ e: e, s: root.score(e, q) }))
            .filter(x => x.s >= 0)
            .sort((a, b) => b.s - a.s)
            .map(x => x.e);
    }

    function launch(e): void {
        if (e.runInTerminal) {
            const command = e.command && e.command.length ? e.command : [Config.cmd.sh, "-c", e.execString];
            Quickshell.execDetached([Config.cmd.terminal, "-e"].concat(command));
        } else {
            e.execute();
        }
    }

    // What the deck asks for: the apps as JSON; one opened as from the
    // launcher ("ok" or "unknown"); a web page in the browser, only http
    // and https ("ok" or "invalid").
    IpcHandler {
        target: "apps"

        function list(): string {
            return JSON.stringify(root.all.map(e => ({ id: e.id, name: e.name, icon: e.icon ?? "" })));
        }
        function launch(id: string): string {
            const entry = root.all.find(e => e.id === id);
            if (!entry)
                return "unknown";
            root.launch(entry);
            return "ok";
        }
        function url(address: string): string {
            if (!/^https?:\/\/[^\s\/?#]+[^\s]*$/i.test(address))
                return "invalid";
            Qt.openUrlExternally(address);
            return "ok";
        }
    }

    // The lock screen, started from here as the launcher starts it: it
    // outlives whoever asked (the shell keeps what it starts).
    IpcHandler {
        target: "session"

        function lock(): void { Quickshell.execDetached([Config.cmd.lock]); }
    }

    function iconFor(appClass: string): string {
        if (!appClass) return "";
        const entry = (typeof DesktopEntries.heuristicLookup === "function")
            ? DesktopEntries.heuristicLookup(appClass)
            : DesktopEntries.byId(appClass);
        return entry?.icon ?? appClass;
    }
}
