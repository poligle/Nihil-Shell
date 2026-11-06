pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config

// The machine's settings as its flake has them (settings.json, /etc/nixos):
// what Preferences and the welcome show and change. Changes wait in `draft`
// until they are applied. Applying asks sudo once, with a finger or with the
// password typed, never both (`auth`), and hands the settings to `nihil
// apply` (modules/nihil-cli.nix), which puts them in place and rebuilds the
// system in a unit of its own: the rebuild restarts this shell and the unit
// goes on; /run/nihil says how it went, and the shell tells when it is done.
// Updating NIHIL (the panel, Updates.qml) goes the same way, through `nihil
// update --unit`: /run/nihil/apply.kind says which.
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
    // failed, why: "password", "finger", "invalid", "busy", "start" (nihil
    // apply could not start the rebuild) or "rebuild" (the rebuild failed).
    property string phase: ""
    property string failure: ""
    // How sudo is being asked: "finger" (nothing typed: the reader, or
    // nothing) or "password" (the one typed, and no finger after it).
    property string auth: ""
    // A finger only where the system as applied has the reader in sudo.
    readonly property bool fingerprint: saved.fingerprint === true
    // A password typed while a finger was awaited: that sudo goes, and this
    // takes its place ({ process, password }).
    property var instead: null
    property string detail: ""
    property string log: ""
    property real since: 0
    readonly property bool busy: phase === "auth" || phase === "applying"
    // What is applied: "settings" (Preferences) or "update" (a newer NIHIL).
    property string kind: "settings"
    readonly property bool updating: kind === "update" && busy

    // Changing the password: "", "busy", "done" or "wrong".
    property string passwordState: ""

    property string wallpaper: ""

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
    readonly property string statusTitle: phase === "auth" ? (auth === "finger" ? Lang.cfgFingerAsk : Lang.cfgChecking)
        : phase === "applying" ? (kind === "update" ? Lang.updApplying : Lang.cfgApplying).arg(elapsed)
        : phase === "failed" ? (failure === "password" ? Lang.cfgWrongPassword : failure === "finger" ? Lang.cfgFingerFailed
            : failure === "invalid" ? Lang.cfgInvalid
            : failure === "busy" ? Lang.cfgBusy : kind === "update" ? Lang.updFailed : Lang.cfgApplyFailed)
        : changes > 0 ? (changes === 1 ? Lang.cfgPendingOne : Lang.cfgPending.arg(changes))
        : phase === "done" ? (kind === "update" ? Lang.updDone : Lang.cfgApplied)
        : phase === "warning" ? Lang.cfgAppliedWarn
        : Lang.cfgSaved
    // Under it, only what says something: the line the rebuild is on, why
    // it failed, where to look.
    readonly property string statusSub: phase === "applying" ? detail
        : phase === "failed" ? (failure === "rebuild" || failure === "start" ? (detail !== "" ? detail : Lang.cfgLogHint) : "")
        : changes === 0 && phase === "warning" ? Lang.cfgLogHint
        : ""

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

    // The desktop's only, at once (the quick picker, drawers/WallpaperPicker.qml).
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

    // With nothing typed and a reader, sudo waits for a finger; with the
    // password, it takes that alone. The settings go first, on a line of
    // their own (the applier writes them to a file for nihil apply).
    function apply(password: string): void {
        if (root.changes === 0 || root.switching(applier, password))
            return;
        root.kind = "settings";
        root.ask(applier, password, JSON.stringify(root.draft) + "\n");
    }

    // The latest NIHIL, and what it pins, in the same unit as applying.
    function update(password: string): void {
        if (root.switching(updater, password))
            return;
        root.kind = "update";
        root.ask(updater, password, "");
    }

    function ask(process: var, password: string, input: string): void {
        root.auth = password === "" && root.fingerprint ? "finger" : "password";
        root.phase = "auth";
        root.failure = "";
        root.detail = "";
        root.log = "";
        process.mode = root.auth;
        process.input = input + (root.auth === "password" ? password + "\n" : "");
        process.running = true;
    }

    // Busy: nothing new, unless it is the password while a finger is
    // awaited, which stops that sudo and goes in its place (on its exit).
    function switching(process: var, password: string): bool {
        if (!root.busy)
            return false;
        if (root.phase === "auth" && root.auth === "finger" && password !== "" && process.running) {
            root.instead = { process: process, password: password, input: process === applier ? JSON.stringify(root.draft) + "\n" : "" };
            process.running = false;
        }
        return true;
    }

    // No finger after all (Cancel while it is awaited).
    function cancelFinger(): void {
        for (const process of [applier, updater]) {
            if (root.phase === "auth" && root.auth === "finger" && process.running) {
                root.instead = { process: process, password: null };
                process.running = false;
            }
        }
    }

    // How a sudo of these ended: true when it was stopped on purpose, for a
    // password typed instead of the finger (on its way now) or for nothing.
    function replaced(process: var): bool {
        if (root.instead === null || root.instead.process !== process)
            return false;
        const next = root.instead;
        root.instead = null;
        if (next.password === null) {
            root.phase = "";
            root.auth = "";
        } else {
            Qt.callLater(() => root.ask(next.process, next.password, next.input));
        }
        return true;
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

    // What /run/nihil says (`peek`): the status, what it is, then the end of the log.
    function report(text: string): void {
        const parts = text.split("--nihil--");
        const status = parts[0].trim();
        if (parts.length > 2 && parts[1].trim() !== "")
            root.kind = parts[1].trim();
        const lines = (parts.length > 2 ? parts[2] : "").split("\n").filter(line => line.trim() !== "");
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
                root.notify(root.kind === "update" ? Lang.updNotifyFailed : Lang.cfgNotifyFailed, Lang.cfgLogHint);
            else
                root.notify(root.kind === "update" ? Lang.updDone : Lang.cfgNotifyApplied, status === "warning" ? Lang.cfgAppliedWarn : "");
            if (root.kind === "update")
                Updates.check();
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

    // sudo, asked once: sh -c sudoAsk sh MODE FILE COMMAND... With the
    // password typed (MODE "password"), its pid, which sudo keeps, goes in
    // a file of the user's first: PAM leaves the reader out for it
    // (modules/hardware.nix) and reads the password from stdin. With nothing
    // typed, sudo waits for a finger, and finds no password if it fails.
    // With a FILE, the first line of stdin, the settings, goes in it.
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string settingsDraft: runtimeDir + "/nihil-settings.json"
    readonly property string sudoAsk: 'umask 077; flag="${XDG_RUNTIME_DIR:-/tmp}/nihil-sudo-password"; '
        + 'if [ "$1" = password ]; then echo $$ > "$flag"; else rm -f "$flag"; fi; '
        + 'if [ -n "$2" ]; then IFS= read -r line && printf "%s\\n" "$line" > "$2" || exit 4; fi; '
        + 'shift 2; exec "$@"'

    // -k: ask even if sudo still remembers it. sudo exits with 1 when
    // neither a finger nor the password did it; nihil apply with 2 (not
    // valid), 3 (busy) or 4 (could not start), saying why on stderr.
    Process {
        id: applier

        property string input: ""
        property string mode: "password"

        command: [Config.cmd.sh, "-c", root.sudoAsk, "sh", mode, root.settingsDraft,
            Config.cmd.sudo, "-k", "-S", "-p", "", Config.cmd.nihil, "apply", root.settingsDraft]
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
            if (root.replaced(applier))
                return;
            if (code === 0) {
                root.phase = "applying";
                root.since = Date.now();
                poll.start();
            } else {
                root.phase = "failed";
                root.failure = code === 1 ? root.auth : code === 2 ? "invalid" : code === 3 ? "busy" : "start";
            }
        }
    }

    // The same, for an update: only the password goes in, if any.
    Process {
        id: updater

        property string input: ""

        property string mode: "password"

        command: [Config.cmd.sh, "-c", root.sudoAsk, "sh", mode, "",
            Config.cmd.sudo, "-k", "-S", "-p", "", Config.cmd.nihil, "update", "--unit"]
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
            if (root.replaced(updater))
                return;
            if (code === 0) {
                root.phase = "applying";
                root.since = Date.now();
                poll.start();
            } else {
                root.phase = "failed";
                root.failure = code === 1 ? root.auth : code === 3 ? "busy" : "start";
            }
        }
    }

    // The current password is typed anyway: no finger after it.
    Process {
        id: passwd

        property string input: ""

        command: [Config.cmd.sh, "-c", root.sudoAsk, "sh", "password", "",
            Config.cmd.sudo, "-k", "-S", "-p", "", Config.cmd.nihil, "passwd"]
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
        command: [Config.cmd.sh, "-c", "cat /run/nihil/apply.status 2>/dev/null; echo --nihil--; cat /run/nihil/apply.kind 2>/dev/null; echo --nihil--; tail -n 60 /run/nihil/apply.log 2>/dev/null"]
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
        // The wallpapers drawer, as SUPER + W opens it (nihil-ipc drawers toggle wallpapers).
        function wallpapers(): void { Drawers.toggle("wallpapers", ""); }
    }
}
