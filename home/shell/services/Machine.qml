pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config

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

    property string phase: ""
    property string failure: ""
    property string auth: ""
    readonly property bool fingerprint: saved.fingerprint === true
    property var instead: null
    property string detail: ""
    property string log: ""
    property real since: 0
    readonly property bool busy: phase === "auth" || phase === "applying"
    property string kind: "settings"
    readonly property bool updating: kind === "update" && busy
    property int target: 0
    property real freed: 0

    property string passwordState: ""

    property string wallpaper: ""
    property bool glass: false

    property var widgets: Config.widgets
    readonly property string widgetsFile: stateDir + "/widgets.json"
    property var timeZones: []

    property real now: Date.now()
    readonly property string elapsed: {
        const seconds = Math.max(0, Math.round((root.now - root.since) / 1000));
        return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
    }
    readonly property bool generational: kind === "generation" || kind === "clean" || kind === "boot"
    readonly property string statusTitle: phase === "auth" ? (auth === "finger" ? Lang.cfgFingerAsk : Lang.cfgChecking)
        : phase === "applying" ? (kind === "update" ? Lang.updApplying : kind === "generation" ? Lang.genSwitching
            : kind === "clean" ? Lang.genCleaning : Lang.cfgApplying).arg(elapsed)
        : phase === "failed" ? (failure === "password" ? Lang.cfgWrongPassword : failure === "finger" ? Lang.cfgFingerFailed
            : failure === "menu" ? Lang.genNotInMenu
            : failure === "invalid" ? (generational ? Lang.genGone : Lang.cfgInvalid)
            : failure === "busy" ? Lang.cfgBusy : kind === "update" ? Lang.updFailed
            : kind === "generation" ? Lang.genSwitchFailed : kind === "clean" ? Lang.genCleanFailed
            : kind === "boot" ? Lang.genBootFailed : Lang.cfgApplyFailed)
        : changes > 0 ? (changes === 1 ? Lang.cfgPendingOne : Lang.cfgPending.arg(changes))
        : phase === "done" ? (kind === "update" ? Lang.updDone : kind === "generation" ? Lang.genSwitched.arg(target)
            : kind === "clean" ? Lang.genCleaned.arg(Dates.bytes(freed)) : kind === "boot" ? Lang.genBootSet.arg(target) : Lang.cfgApplied)
        : phase === "warning" ? (kind === "generation" ? Lang.genSwitchedWarn.arg(target) : Lang.cfgAppliedWarn)
        : Lang.cfgSaved
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

    function hide(): void {
        if (!root.welcoming)
            root.shown = false;
    }

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

    function liveWallpaper(name: string): void {
        if (name === "")
            return;
        root.wallpaper = name;
        Quickshell.execDetached([Config.cmd.wallpaper, "set", name]);
    }

    function setWallpaper(name: string): void {
        liveWallpaper(name);
    }

    function setGlass(on: bool): void {
        root.glass = on;
        Quickshell.execDetached([Config.cmd.wallpaper, "glass", on ? "on" : "off"]);
    }

    function apply(password: string): void {
        if (root.changes === 0 || root.switching(applier, password))
            return;
        root.kind = "settings";
        root.ask(applier, password, JSON.stringify(root.draft) + "\n");
    }

    function update(password: string): void {
        if (root.switching(updater, password))
            return;
        root.kind = "update";
        root.ask(updater, password, "");
    }

    function generation(action: string, value: int, password: string): void {
        if (root.switching(generator, password))
            return;
        root.kind = action === "switch" ? "generation" : action;
        root.target = action === "clean" ? 0 : value;
        generator.action = action;
        generator.value = value;
        root.ask(generator, password, "");
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

    function switching(process: var, password: string): bool {
        if (!root.busy)
            return false;
        if (root.phase === "auth" && root.auth === "finger" && password !== "" && process.running) {
            root.instead = { process: process, password: password, input: process === applier ? JSON.stringify(root.draft) + "\n" : "" };
            process.running = false;
        }
        return true;
    }

    function cancelFinger(): void {
        for (const process of [applier, updater, generator]) {
            if (root.phase === "auth" && root.auth === "finger" && process.running) {
                root.instead = { process: process, password: null };
                process.running = false;
            }
        }
    }

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

    function cause(lines: var): string {
        for (let i = 0; i < lines.length; i++) {
            if (/^\s*error:/.test(lines[i]))
                return lines[i].trim();
        }
        return lines.length > 0 ? lines[lines.length - 1].trim() : "";
    }

    readonly property string counting: "awk '/^these [0-9]+ derivations? will be built/ { total += $2 } "
        + "/^this derivation will be built/ { total += 1 } /^these [0-9]+ paths? will be fetched/ { total += $2 } "
        + "/^this path will be fetched/ { total += 1 } /^building .\\/nix\\/store\\// || /^copying path .\\/nix\\/store\\// { begun += 1 } "
        + "/^activating the configuration/ { active = 1 } END { print total + 0, begun + 0, active + 0 }'"

    function progress(counts: string): void {
        const numbers = counts.trim().split(/\s+/).map(Number);
        if (numbers.length < 3 || numbers.some(isNaN))
            return;
        const [total, begun, active] = numbers;
        Glyph.track("rebuild", active ? 0.95 : total > 0 ? 0.05 + 0.85 * Math.min(1, begun / total) : -1);
    }

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
            if (parts.length > 3)
                root.progress(parts[3]);
            poll.start();
        } else if (root.phase === "applying" && (status === "done" || status === "warning" || status === "failed")) {
            poll.stop();
            Glyph.finish("rebuild", status === "failed" ? "failed" : "done");
            root.log = lines.join("\n");
            root.detail = status === "failed" ? root.cause(lines) : (lines.length > 0 ? lines[lines.length - 1].trim() : "");
            root.facts(lines);
            root.phase = status;
            root.failure = status === "failed" ? "rebuild" : "";
            if (status === "failed")
                root.notify(root.kind === "update" ? Lang.updNotifyFailed : root.kind === "generation" ? Lang.genSwitchFailed
                    : root.kind === "clean" ? Lang.genCleanFailed : Lang.cfgNotifyFailed, Lang.cfgLogHint);
            else if (root.kind === "generation")
                root.notify((status === "warning" ? Lang.genSwitchedWarn : Lang.genSwitched).arg(root.target), "");
            else if (root.kind === "clean")
                root.notify(Lang.genCleaned.arg(Dates.bytes(root.freed)), "");
            else
                root.notify(root.kind === "update" ? Lang.updDone : Lang.cfgNotifyApplied, status === "warning" ? Lang.cfgAppliedWarn : "");
            if (root.kind === "update")
                Updates.check();
            if (root.generational)
                Generations.refresh(root.kind === "clean");
        }
    }

    function facts(lines: var): void {
        for (let i = 0; i < lines.length; i++) {
            const to = /^nihil: generation ([0-9]+)$/.exec(lines[i].trim());
            if (to)
                root.target = Number(to[1]);
            const freed = /^nihil: freed ([0-9]+)$/.exec(lines[i].trim());
            if (freed)
                root.freed = Number(freed[1]);
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

    Process {
        command: [Config.cmd.wallpaper, "glass"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.glass = text.trim() === "on"
        }
    }

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string settingsDraft: runtimeDir + "/nihil-settings.json"
    readonly property string sudoAsk: 'umask 077; flag="${XDG_RUNTIME_DIR:-/tmp}/nihil-sudo-password"; '
        + 'if [ "$1" = password ]; then echo $$ > "$flag"; else rm -f "$flag"; fi; '
        + 'if [ -n "$2" ]; then IFS= read -r line && printf "%s\\n" "$line" > "$2" || exit 4; fi; '
        + 'shift 2; exec "$@"'

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

    Process {
        id: generator

        property string input: ""
        property string mode: "password"
        property string action: "boot"
        property int value: 0

        command: [Config.cmd.sh, "-c", root.sudoAsk, "sh", mode, "",
            Config.cmd.sudo, "-k", "-S", "-p", "", Config.cmd.nihil, "generations", action, String(value)]
            .concat(action === "boot" ? [] : ["--unit"])
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
            if (root.replaced(generator))
                return;
            if (code === 0 && generator.action === "boot") {
                root.phase = "done";
                root.detail = "";
                Generations.refresh(false);
            } else if (code === 0) {
                root.phase = "applying";
                root.since = Date.now();
                poll.start();
            } else {
                root.phase = "failed";
                root.failure = code === 1 ? root.auth : code === 2 ? "invalid" : code === 3 ? "busy" : code === 5 ? "menu" : "start";
            }
        }
    }

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
        command: [Config.cmd.sh, "-c", "cat /run/nihil/apply.status 2>/dev/null; echo --nihil--; cat /run/nihil/apply.kind 2>/dev/null; echo --nihil--; tail -n 60 /run/nihil/apply.log 2>/dev/null; echo --nihil--; " + root.counting + " /run/nihil/apply.log 2>/dev/null"]
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
        function wallpapers(): void { Drawers.toggle("wallpapers", ""); }
    }
}
