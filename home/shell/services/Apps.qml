pragma Singleton

import QtQuick
import Quickshell
import qs.config

// Desktop entries and a small fuzzy search for the launcher.
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

    function iconFor(appClass: string): string {
        if (!appClass) return "";
        const entry = (typeof DesktopEntries.heuristicLookup === "function")
            ? DesktopEntries.heuristicLookup(appClass)
            : DesktopEntries.byId(appClass);
        return entry?.icon ?? appClass;
    }
}
