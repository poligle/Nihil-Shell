pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config

// The machine's settings as its flake has them (settings.json, /etc/nixos):
// what Preferences and the welcome show and change. Changes wait in `draft`
// until they are applied. Applying hands the password to sudo and the
// settings to `nihil apply` (modules/nihil-cli.nix), which puts them in place
// and rebuilds the system in a unit of its own: the rebuild restarts this
// shell and the unit goes on; /run/nihil says how it went, and the shell
// tells when it is done.
//   nihil-ipc settings open | toggle | close | welcome | page <name>
Singleton {
    id: root

    property var saved: ({})
    property var draft: ({})
    property bool loaded: false
    readonly property int changes: loaded ? differences(saved, draft) : 0

    property bool shown: false
    property string page: "you"
    property bool welcoming: false
    property string screen: ""

    // Applying: "", "auth", "applying", "done", "warning" or "failed"; when it
    // failed, why: "password", "invalid", "busy", "start" (nihil apply could
    // not start the rebuild) or "rebuild" (the rebuild failed).
    property string phase: ""
    property string failure: ""
    property string detail: ""
    property string log: ""
    property real since: 0
    readonly property bool busy: phase === "auth" || phase === "applying"

    // Changing the password: "", "busy", "done" or "wrong".
    property string passwordState: ""

    property string wallpaper: ""
    property bool picking: false

    // The desktop widgets that show (background/Desktop.qml): the user's
    // choice, kept in their state, or all of them.
    property var widgets: Config.widgets
    readonly property string widgetsFile: stateDir + "/widgets.json"
    property var timeZones: []

    // How applying goes, in words, for Preferences and the welcome.
    property real now: Date.now()
    readonly property string elapsed: {
        const seconds = Math.max(0, Math.round((root.now - root.since) / 1000));
        return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
    }
    readonly property string statusTitle: phase === "auth" ? Lang.cfgChecking
        : phase === "applying" ? Lang.cfgApplying.arg(elapsed)
        : phase === "failed" ? (failure === "password" ? Lang.cfgWrongPassword : failure === "invalid" ? Lang.cfgInvalid
            : failure === "busy" ? Lang.cfgBusy : Lang.cfgApplyFailed)
        : changes > 0 ? (changes === 1 ? Lang.cfgPendingOne : Lang.cfgPending.arg(changes))
        : phase === "done" ? Lang.cfgApplied
        : phase === "warning" ? Lang.cfgAppliedWarn
        : Lang.cfgSaved
    readonly property string statusSub: phase === "auth" ? (get("fingerprint", false) ? Lang.cfgApplyFinger : "")
        : phase === "applying" ? (detail !== "" ? detail : Lang.cfgApplyingSub)
        : phase === "failed" ? (failure === "rebuild" || failure === "start" ? (detail !== "" ? detail : Lang.cfgLogHint) : "")
        : changes > 0 ? Lang.cfgPendingSub
        : phase === "warning" ? Lang.cfgLogHint
        : phase === "done" ? "" : Lang.cfgSavedSub

    Timer {
        running: root.phase === "applying"
        interval: 1000
        repeat: true
        onTriggered: root.now = Date.now()
    }

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/nihil"

    function clone(value: var): var {
        return JSON.parse(JSON.stringify(value === undefined ? {} : value));
    }

    function get(path: string, fallback: var): var {
        let node = root.draft;
        const keys = path.split(".");
        for (let i = 0; i < keys.length; i++) {
            if (node === null || typeof node !== "object" || !(keys[i] in node))
                return fallback;
            node = node[keys[i]];
        }
        return node;
    }

    // undefined takes the value out: back to NIHIL's own (binds, gestures).
    function set(path: string, value: var): void {
        const next = clone(root.draft);
        const keys = path.split(".");
        let node = next;
        for (let i = 0; i < keys.length - 1; i++) {
            if (node[keys[i]] === null || typeof node[keys[i]] !== "object")
                node[keys[i]] = {};
            node = node[keys[i]];
        }
        const last = keys[keys.length - 1];
        if (value === undefined)
            delete node[last];
        else
            node[last] = value;
        root.draft = next;
    }

    function differences(a: var, b: var): int {
        if (a === null || b === null || typeof a !== "object" || typeof b !== "object")
            return JSON.stringify(a) === JSON.stringify(b) ? 0 : 1;
        let count = 0;
        const keys = Object.keys(a).concat(Object.keys(b).filter(key => !(key in a)));
        for (let i = 0; i < keys.length; i++)
            count += differences(a[keys[i]], b[keys[i]]);
        return count;
    }

    function discard(): void {
        root.draft = clone(root.saved);
        if (!root.busy)
            root.phase = "";
    }

    function show(name: string, welcome: bool): void {
        root.screen = Hyprland.focusedMonitor?.name ?? "";
        root.welcoming = welcome;
        root.page = name !== "" ? name : (welcome ? "hello" : "you");
        root.shown = true;
        if (root.timeZones.length === 0 && !zones.running)
            zones.running = true;
    }

    // The welcome only goes away when it ends or is skipped.
    function hide(): void {
        if (!root.welcoming)
            root.shown = false;
    }

    // Seen once: skipping it counts. Written before applying, so the restart
    // the rebuild brings does not show it again.
    function markWelcomed(): void {
        Quickshell.execDetached([Config.cmd.sh, "-c", "mkdir -p \"$1\" && touch \"$1/welcomed\"", "sh", root.stateDir]);
    }

    function endWelcome(): void {
        markWelcomed();
        root.welcoming = false;
        root.shown = false;
    }

    function setWidget(name: string, on: bool): void {
        const next = root.widgets.filter(widget => widget !== name);
        if (on)
            next.push(name);
        root.widgets = next;
        Quickshell.execDetached([Config.cmd.sh, "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "sh", root.widgetsFile, JSON.stringify(next)]);
    }

    // The desktop's only, at once (the quick picker, settings/Wallpapers.qml).
    function liveWallpaper(name: string): void {
        if (name === "")
            return;
        root.wallpaper = name;
        Quickshell.execDetached([Config.cmd.wallpaper, "set", name]);
    }

    // At once; the lock screen and the login follow it (nihil-wallpaper).
    function setWallpaper(name: string): void {
        liveWallpaper(name);
    }

    function apply(password: string): void {
        if (root.busy || root.changes === 0)
            return;
        root.phase = "auth";
        root.failure = "";
        root.detail = "";
        root.log = "";
        applier.input = password + "\n" + JSON.stringify(root.draft, null, 2) + "\n";
        applier.running = true;
    }

    function changePassword(current: string, next: string): void {
        if (passwd.running)
            return;
        root.passwordState = "busy";
        passwd.input = current + "\n" + Config.user + ":" + next + "\n";
        passwd.running = true;
    }

    function notify(title: string, body: string): void {
        Quickshell.execDetached([Config.cmd.notifySend, "-a", "NIHIL", title, body]);
    }

    // The line that says why a rebuild failed: Nix's error, else the last one.
    function cause(lines: var): string {
        for (let i = 0; i < lines.length; i++) {
            if (/^\s*error:/.test(lines[i]))
                return lines[i].trim();
        }
        return lines.length > 0 ? lines[lines.length - 1].trim() : "";
    }

    // What /run/nihil says (`peek`): the status, then the end of the log.
    function report(text: string): void {
        const parts = text.split("--nihil--");
        const status = parts[0].trim();
        const lines = (parts.length > 1 ? parts[1] : "").split("\n").filter(line => line.trim() !== "");
        if (status === "running") {
            root.log = lines.join("\n");
            if (lines.length > 0)
                root.detail = lines[lines.length - 1].trim();
            if (root.phase !== "applying") {
                root.phase = "applying";
                root.since = Date.now();
            }
            poll.start();
        } else if (root.phase === "applying" && (status === "done" || status === "warning" || status === "failed")) {
            poll.stop();
            root.log = lines.join("\n");
            root.detail = status === "failed" ? root.cause(lines) : (lines.length > 0 ? lines[lines.length - 1].trim() : "");
            root.phase = status;
            root.failure = status === "failed" ? "rebuild" : "";
            if (status === "failed")
                root.notify(Lang.cfgNotifyFailed, Lang.cfgLogHint);
            else
                root.notify(Lang.cfgNotifyApplied, status === "warning" ? Lang.cfgAppliedWarn : "");
        }
    }

    FileView {
        path: Config.settingsFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const next = JSON.parse(text());
                const pending = root.loaded && root.differences(root.saved, root.draft) > 0;
                root.saved = next;
                if (!pending)
                    root.draft = root.clone(next);
                root.loaded = true;
            } catch (error) {
                console.warn("nihil: settings:", path, "is not valid JSON:", error);
            }
        }
    }

    // The first time, the welcome, once the session has settled.
    Process {
        command: [Config.cmd.sh, "-c", "[ -e \"$1\" ]", "sh", root.stateDir + "/welcomed"]
        running: true
        onExited: code => {
            if (code !== 0)
                welcomeDelay.start();
        }
    }

    Timer {
        id: welcomeDelay
        interval: 2500
        onTriggered: root.show("hello", true)
    }

    Process {
        id: zones
        command: [Config.cmd.timedatectl, "list-timezones", "--no-pager"]
        stdout: StdioCollector {
            onStreamFinished: root.timeZones = text.split("\n").filter(zone => zone !== "")
        }
    }

    Process {
        command: [Config.cmd.sh, "-c", "cat \"$1\" 2>/dev/null", "sh", root.widgetsFile]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const chosen = JSON.parse(text);
                    if (Array.isArray(chosen))
                        root.widgets = chosen;
                } catch (error) {
                }
            }
        }
    }

    Process {
        command: [Config.cmd.wallpaper, "current"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.wallpaper = text.trim()
        }
    }

    // sudo reads the first line, the password; nihil apply the rest. -k: ask
    // even if sudo still remembers it, or the password would go on to nihil.
    // sudo exits with 1 when the password is wrong; nihil apply with 2 (not
    // valid), 3 (busy) or 4 (could not start), saying why on stderr.
    Process {
        id: applier

        property string input: ""

        command: [Config.cmd.sudo, "-k", "-S", "-p", "", Config.cmd.nihil, "apply", "-"]
        stdinEnabled: true
        onStarted: {
            write(input);
            input = "";
            stdinEnabled = false;
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    root.detail = line.trim();
            }
        }
        onExited: code => {
            stdinEnabled = true;
            if (code === 0) {
                root.phase = "applying";
                root.since = Date.now();
                poll.start();
            } else {
                root.phase = "failed";
                root.failure = code === 1 ? "password" : code === 2 ? "invalid" : code === 3 ? "busy" : "start";
            }
        }
    }

    Process {
        id: passwd

        property string input: ""

        command: [Config.cmd.sudo, "-k", "-S", "-p", "", Config.cmd.nihil, "passwd"]
        stdinEnabled: true
        onStarted: {
            write(input);
            input = "";
            stdinEnabled = false;
        }
        onExited: code => {
            stdinEnabled = true;
            root.passwordState = code === 0 ? "done" : "wrong";
        }
    }

    // While it applies, how it goes, every second; once at the start too, in
    // case this shell is the one the rebuild restarted.
    Timer {
        id: poll
        interval: 1000
        repeat: true
        onTriggered: {
            if (!peek.running)
                peek.running = true;
        }
    }

    Process {
        id: peek
        command: [Config.cmd.sh, "-c", "cat /run/nihil/apply.status 2>/dev/null; echo --nihil--; tail -n 60 /run/nihil/apply.log 2>/dev/null"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.report(text)
        }
    }

    IpcHandler {
        target: "settings"

        function open(): void { root.show("", false); }
        function page(name: string): void { root.show(name, false); }
        function toggle(): void { if (root.shown) root.hide(); else root.show("", false); }
        function close(): void { root.hide(); }
        function welcome(): void { root.show("hello", true); }
        function wallpapers(): void {
            root.screen = Hyprland.focusedMonitor?.name ?? "";
            root.picking = !root.picking;
        }
    }
}
