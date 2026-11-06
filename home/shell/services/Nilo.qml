pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config

// Nilo, the assistant: the shell's side of home/nilo/agent.py. The agent
// starts the first time Nilo opens and stays (it holds the conversation and
// any download); it speaks one JSON object per line. The model itself lives
// in Ollama and goes to sleep on its own after `settings.keepAlive` minutes.
// Opening apps is done here, where the desktop entries are (open_app).
//   qs -c nihil ipc call nilo toggle|open|sleep      nilo ask "..."
Singleton {
    id: root

    readonly property bool enabled: Config.nilo.enabled

    // Agent: `ready` once it runs, `known` once it has said hello.
    property bool wanted: false
    property bool ready: false
    property bool known: false
    property var queued: []
    property int restarts: 0

    // Mirror of the agent's settings and catalogue
    property var settings: ({})
    property var models: []
    property string recommended: ""
    property string fast: ""              // the model auto uses for simple questions
    property string inUse: ""             // the model of the latest answer
    property real ramGB: 0
    property bool ollama: true

    // Ollama's service when it is down: { starting, up, error, unit,
    // activeState, subState, result, log } (systemctl show and the journal).
    property var service: ({})
    readonly property bool startingOllama: service.starting === true

    // Git repositories under ~, for the settings (most recently used first).
    property var repos: []

    // The model in Ollama
    property bool loaded: false
    property bool loading: false
    property real expires: 0
    property real sizeGB: 0
    property int gpu: 0

    // The conversation. `phase`: idle, waiting (for the first word), thinking,
    // writing, tool (one is running) or confirm (waiting for the user).
    readonly property ListModel messages: ListModel {}
    property bool busy: false
    property string phase: "idle"
    property string tool: ""
    property var confirm: null
    property bool stopping: false
    property int pulse: 0           // one per word written: the eyes bounce
    property string mood: ""        // a passing expression: "happy" or "error"

    // A download: { model, status, progress (0..1), error }
    property var pull: null

    // The launcher on screen is in "?" mode (set by Launcher.qml).
    property bool shown: false
    property bool summon: false
    signal summoned()

    // The answer goes on with the launcher closed (esc, a click outside, an
    // app it opened): when it ends, or when it needs a confirmation, Nilo
    // sends a notification. Notifs.qml lights the frame from the left and,
    // instead of a popup, this panel comes out of the bar next to the eyes
    // (nilo/Peek.qml); with do not disturb on, only the history keeps it.
    property bool behind: false
    property bool peeking: false
    property string peekKind: ""        // done, confirm or error
    property string peekScreen: ""
    property string peekQuestion: ""
    property string peekText: ""
    property var peekFacts: ({})        // the confirmation, or the answer's stats

    onShownChanged: {
        if (shown) {
            behind = false;
            unpeek();
            Notifs.dismissTag("nilo");
        } else if (busy) {
            behind = true;
        }
    }

    readonly property bool onboarded: settings.onboarded === true
    readonly property var current: models.find(m => m.tag === settings.model) ?? null
    readonly property bool installed: current?.installed === true

    function start(): void {
        if (!enabled || wanted) return;
        wanted = true;
        agent.running = true;
    }

    function send(request: var): void {
        if (!enabled) return;
        start();
        if (agent.running && ready) agent.write(JSON.stringify(request) + "\n");
        else queued = queued.concat([request]);
    }

    // --- Opening ----------------------------------------------------------------

    // Off, it still opens: the launcher explains how to turn it on.
    function open(): void {
        start();
        summon = true;
        if (Drawers.current === "launcher") summoned();
        else Drawers.open("launcher", "", false);
    }

    function toggle(): void {
        if (shown && Drawers.current === "launcher") Drawers.close();
        else open();
    }

    // --- Away from the launcher -------------------------------------------------

    // The screen of the panel: the focused one if it has the bar (and the eyes).
    function barScreen(): string {
        const focused = Hyprland.focusedMonitor?.name ?? "";
        const bars = Config.barOutputs;
        if (bars.indexOf(focused) >= 0) return focused;
        return bars.indexOf(Config.primaryOutput) >= 0 ? Config.primaryOutput : (bars[0] ?? focused);
    }

    // The last message of a kind in the latest exchange (after its question).
    function latest(kind: string): var {
        for (let i = messages.count - 1; i >= 0; i--) {
            const m = messages.get(i);
            if (m.kind === kind) return m;
            if (m.kind === "user") break;
        }
        return null;
    }

    function plain(text: string): string {
        return String(text ?? "")
            .replace(/```[\s\S]*?```/g, " … ")
            .replace(/\[([^\]\n]+)\]\([^)\s]+\)/g, "$1")
            .replace(/[*_`#>]/g, "")
            .replace(/\s+/g, " ")
            .trim();
    }

    function confirmText(c: var): string {
        if (!c) return "";
        if (c.action === "run" || c.action === "terminal") return "$ " + (c.command ?? "");
        if (c.action === "edit" || c.action === "create")
            return (c.action === "create" ? Lang.confirmCreate : Lang.confirmEdit) + " " + (c.path ?? "");
        return c.message ? "git commit: " + c.message : "git " + (c.action === "push" ? Lang.confirmPush : Lang.confirmCommit);
    }

    // What the panel shows, and the notification that brings it.
    function tell(kind: string): void {
        const question = latest("user");
        const reply = latest("nilo");
        const failure = latest("error");
        peekKind = kind;
        peekQuestion = question ? question.text : "";
        peekText = kind === "confirm" ? confirmText(confirm)
            : kind === "error" ? (failure ? errorText(failure.name, failure.text) : "")
            : (reply ? reply.text : "");
        peekFacts = kind === "confirm" ? (confirm ?? {}) : (() => { try { return JSON.parse(reply?.info || "{}"); } catch (e) { return {}; } })();
        const body = plain(peekText);
        Quickshell.execDetached([Config.cmd.notifySend, "--app-name=Nilo", "--hint=string:x-nihil-tag:nilo",
                                 "--hint=string:x-nihil-nilo:" + kind,
                                 kind === "confirm" ? Lang.niloPeekWaiting : kind === "error" ? Lang.niloPeekFailed : Lang.niloPeekDone,
                                 (body.length > 220 ? body.slice(0, 219) + "…" : body)
                                     .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")]);
    }

    // Notifs.qml, once the notification is in: out of the bar it comes.
    function peek(kind: string): void {
        if (shown || kind !== peekKind) return;
        peekScreen = barScreen();
        peekUntil = Date.now() + (kind === "confirm" ? 30 : peekSeconds) * 1000;
        peeking = true;
    }

    function unpeek(): void {
        peeking = false;
    }

    // The panel goes back on its own, clicked or not: after a few seconds,
    // more for longer answers, half a minute for a confirmation (then the
    // eyes in the bar keep waiting with it). The pointer moving over it
    // buys a few more; a pointer resting there doesn't.
    readonly property int peekSeconds: Math.min(20, 7 + Math.ceil(plain(peekText).length / 45))
    property real peekUntil: 0

    function peekTouch(): void {
        if (peeking) peekUntil = Math.max(peekUntil, Date.now() + 4000);
    }

    Timer {
        interval: 500
        repeat: true
        running: root.peeking
        onTriggered: if (Date.now() >= root.peekUntil) root.unpeek()
    }

    // --- Requests ---------------------------------------------------------------

    function ask(text: string): void {
        const question = text.trim();
        if (!question || busy) return;
        if (quickOpen(question)) return;
        messages.append({ kind: "user", text: question, done: true, name: "", status: "", info: "", cid: "" });
        busy = true;
        phase = "waiting";
        mood = "";
        send({ op: "ask", text: question });
    }

    function stop(): void {
        if (!busy) return;
        stopping = true;
        send({ op: "stop" });
    }

    function reset(): void {
        if (busy) stop();
        messages.clear();
        confirm = null;
        send({ op: "reset" });
    }

    function answer(ok: bool): void {
        if (!confirm) return;
        send({ op: "confirm", id: confirm.id, ok: ok });
    }

    function set(key: string, value: var): void {
        const next = Object.assign({}, settings);
        next[key] = value;
        settings = next;
        send({ op: "set", key: key, value: value });
    }

    function download(tag: string): void {
        pull = { model: tag, status: "starting", progress: 0, error: "", code: "" };
        send({ op: "pull", model: tag });
    }

    // The agent tries on its own; this is the button (it may ask for a password).
    function startOllama(): void {
        if (startingOllama) return;
        service = Object.assign({}, service, { starting: true, error: "" });
        send({ op: "startOllama" });
    }

    function findRepos(): void { send({ op: "repos" }); }

    // ~/.config/nihil/nilo.md, made by the agent if missing, in the editor.
    function editNotes(): void { send({ op: "notes" }); }

    // "abre zen", "open zen and thunar": with Apps allowed, these open
    // right away, without waiting for the model: the launcher's own search,
    // and only when every name matches an app closely (or is a web address).
    // Anything else, or anything more ("abre zen y busca el tiempo"), goes to
    // Nilo as usual. The agent doesn't hear of it.
    readonly property var opener: /^(?:[áa]bre(?:me)?|abrir|lanza|arranca|open|launch|start)\s+(.+?)[.!]*$/i

    function quickOpen(text: string): bool {
        if (settings.apps !== true) return false;
        const m = text.match(opener);
        if (!m) return false;
        const targets = m[1].split(/\s*,\s*|\s+(?:y|e|and)\s+/i)
            .map(t => t.replace(/^(?:el|la|los|las|the|an?)\s+/i, "").trim())
            .filter(t => t !== "");
        if (targets.length === 0 || targets.length > 4) return false;
        const plan = [];
        for (const t of targets) {
            if (/^(?:https?:\/\/|mailto:)\S+$/i.test(t)) {
                plan.push({ url: t, name: t });
                continue;
            }
            const q = t.toLowerCase();
            const hits = Apps.search(q);
            if (hits.length === 0 || Apps.score(hits[0], q) < 400) return false;
            plan.push({ entry: hits[0], name: hits[0].name });
        }
        messages.append({ kind: "user", text: text, done: true, name: "", status: "", info: "", cid: "" });
        for (const p of plan) {
            messages.append({ kind: "tool", text: "", done: true, name: "open_app", status: "done", cid: "",
                              info: JSON.stringify({ ok: true, opened: p.name, args: { target: p.name } }) });
            if (p.entry) Apps.launch(p.entry);
            else Qt.openUrlExternally(p.url);
        }
        Drawers.close();
        return true;
    }

    // open_app: an app by its name, as the launcher finds it (only a good
    // match: a name, a word of it or its keywords), or a path or an address
    // in whatever opens it. The launcher closes, as when an app is opened
    // from it; the answer goes on without it.
    function launch(target: string, kind: string): var {
        if (kind === "url" || kind === "path") {
            const ok = Qt.openUrlExternally(kind === "path" ? "file://" + encodeURI(target) : target);
            if (ok) Drawers.close();
            return ok ? { ok: true, name: target } : { ok: false, error: "nothing opens " + target };
        }
        const q = String(target ?? "").trim().toLowerCase();
        const found = q ? Apps.search(q) : [];
        const best = found.length > 0 && Apps.score(found[0], q) >= 200 ? found[0] : null;
        if (!best) return { ok: false, similar: found.slice(0, 5).map(e => e.name) };
        Drawers.close();
        Apps.launch(best);
        return { ok: true, name: best.name };
    }

    function cancelDownload(): void { send({ op: "cancelPull" }); }
    function remove(tag: string): void { send({ op: "delete", model: tag }); }
    function sleep(): void { send({ op: "sleep" }); }

    // The user started typing: load the model so the answer starts sooner.
    function warm(): void {
        if (known && installed && !loaded && !loading) {
            loading = true;
            send({ op: "warm" });
        }
    }

    // --- Events -----------------------------------------------------------------

    function last(): var {
        return messages.count > 0 ? messages.get(messages.count - 1) : null;
    }

    function findTool(id: string): int {
        for (let i = messages.count - 1; i >= 0; i--)
            if (messages.get(i).cid === id) return i;
        return -1;
    }

    function errorText(code: string, detail: string): string {
        const model = settings.model ?? "";
        switch (code) {
        case "ollama-down": return Lang.niloErrOllama;
        case "model-missing": return Lang.niloErrModel.arg(model);
        case "memory": return Lang.niloErrMemory.arg(model);
        case "no-model": return Lang.niloErrNoModel;
        case "bad-repo": return Lang.niloErrRepo.arg(detail);
        }
        return Lang.niloErrOther.arg((detail || code).slice(0, 160));
    }

    function catalogue(e: var): void {
        models = e.models ?? [];
        recommended = e.recommended ?? "";
        fast = e.fast ?? "";
        ramGB = e.ramGB ?? 0;
        ollama = e.ollama !== false;
    }

    function handle(line: string): void {
        let e;
        try { e = JSON.parse(line); } catch (err) { console.log("nilo: bad line " + line); return; }

        switch (e.ev) {
        case "hello":
            settings = e.settings;
            catalogue(e);
            known = true;
            restarts = 0;
            break;
        case "settings":
            settings = e.settings;
            break;
        case "models":
            catalogue(e);
            if (pull && pull.status === "success") pull = null;
            break;
        case "state":
            if (e.model) inUse = e.model;
            loaded = e.loaded;
            loading = e.loading;
            expires = e.expires ?? 0;
            sizeGB = e.sizeGB ?? 0;
            gpu = e.gpu ?? 0;
            if (e.ollama !== null && e.ollama !== undefined) {
                // It just went down: what systemd said last time no longer applies.
                if (ollama && e.ollama === false) service = ({});
                ollama = e.ollama;
            }
            break;
        case "ollama":
            service = e;
            if (e.up === true) {
                ollama = true;
                // A download that failed only because Ollama was down can go again.
                if (pull && pull.code === "ollama-down") pull = null;
            } else if (e.up === false) {
                ollama = false;
            }
            break;
        case "repos":
            repos = e.repos ?? [];
            break;
        case "notes":
            // In Neovim, in kitty, whatever the system would open a .md
            // with (the notes start with a comment, which may pass for HTML).
            Drawers.close();
            Quickshell.execDetached([Config.cmd.terminal, "-e", Config.cmd.editor, e.path]);
            break;
        case "reset":
            break;
        case "start":
            busy = true;
            phase = "waiting";
            inUse = e.model ?? "";
            break;
        case "thinking":
            if (phase === "waiting") phase = "thinking";
            break;
        case "token": {
            const l = last();
            if (l && l.kind === "nilo" && !l.done)
                messages.setProperty(messages.count - 1, "text", l.text + e.text);
            else
                messages.append({ kind: "nilo", text: e.text.replace(/^\s+/, ""), done: false, name: "", status: "", info: "", cid: "" });
            phase = "writing";
            pulse++;
            break;
        }
        case "tool":
            if (e.status === "running") {
                closeReply();
                messages.append({ kind: "tool", text: "", done: false, name: e.name, status: "running",
                                  info: JSON.stringify(e.args ?? {}), cid: e.id });
                phase = "tool";
                tool = e.name;
            } else {
                const i = findTool(e.id);
                if (i >= 0) {
                    const args = JSON.parse(messages.get(i).info || "{}");
                    // Declined (git, a file change or a command) is not a failure: it says "cancelled".
                    messages.set(i, { done: true, status: e.ok || e.declined ? "done" : "failed",
                                      info: JSON.stringify(Object.assign({}, e, { args: args })),
                                      text: e.tail ? e.tail.join("\n") : messages.get(i).text });
                }
                if (e.name === "git_commit" && e.ok && !e.declined) mood = "happy";
                phase = "waiting";
                tool = "";
            }
            break;
        case "output": {
            // A command's last lines while it runs.
            const i = findTool(e.id);
            if (i >= 0) messages.setProperty(i, "text", (e.lines ?? []).join("\n"));
            break;
        }
        case "launch":
            send(Object.assign({ op: "launched", id: e.id }, launch(e.target, e.kind)));
            break;
        case "confirm":
            confirm = e;
            messages.append({ kind: "confirm", text: "", done: false, name: e.action, status: "asking",
                              info: JSON.stringify(e), cid: e.id });
            phase = "confirm";
            if (!shown) tell("confirm");
            break;
        case "confirmed": {
            const i = findTool(e.id);
            if (i >= 0) messages.set(i, { done: true, status: e.ok ? "ok" : "declined" });
            confirm = null;
            phase = "tool";
            if (peeking && peekKind === "confirm") unpeek();
            break;
        }
        case "done": {
            closeReply();
            const l = last();
            if (e.cancelled)
                messages.append({ kind: "note", text: "", done: true, name: "stopped", status: "", info: "", cid: "" });
            else if (l && l.kind === "nilo" && e.stats && e.stats.tokens)
                messages.setProperty(messages.count - 1, "info", JSON.stringify(e.stats));
            if (behind && !shown && !e.cancelled) tell(e.failed ? "error" : "done");
            behind = false;
            busy = false;
            stopping = false;
            phase = "idle";
            tool = "";
            confirm = null;
            break;
        }
        case "error":
            // It was still on the previous answer: that question never went in.
            if (e.code === "busy") {
                const l = last();
                if (l && l.kind === "user") messages.remove(messages.count - 1);
                busy = false;
                phase = "idle";
                break;
            }
            messages.append({ kind: "error", text: e.detail ?? "", done: true, name: e.code, status: "", info: "", cid: "" });
            mood = "error";
            moodReset.restart();
            break;
        case "pull":
            if (e.status === "error" || e.status === "cancelled" || e.status === "busy") {
                pull = e.status === "error" ? { model: e.model, status: "error", progress: 0, error: e.detail ?? "", code: e.code ?? "" } : null;
            } else {
                pull = { model: e.model, status: e.status, error: "", code: "",
                         attempt: e.attempt ?? 0, attempts: e.attempts ?? 0,
                         progress: e.total > 0 ? e.completed / e.total : (pull?.progress ?? 0) };
            }
            break;
        }
    }

    function closeReply(): void {
        const l = last();
        if (l && l.kind === "nilo" && !l.done) {
            messages.setProperty(messages.count - 1, "done", true);
            messages.setProperty(messages.count - 1, "text", l.text.replace(/\s+$/, ""));
        }
    }

    Timer {
        id: moodReset
        interval: 3200
        onTriggered: root.mood = ""
    }

    onMoodChanged: if (mood === "happy") moodReset.restart()

    // --- The agent --------------------------------------------------------------

    Process {
        id: agent
        command: [Config.nilo.agent]
        stdinEnabled: true

        stdout: SplitParser {
            onRead: data => root.handle(data)
        }
        // Into the shell's journal: journalctl --user -u nihil-shell
        stderr: SplitParser {
            onRead: data => console.log("nilo: " + data)
        }

        onStarted: {
            root.ready = true;
            agent.write(JSON.stringify({ op: "hello" }) + "\n");
            const pending = root.queued;
            root.queued = [];
            for (const request of pending) agent.write(JSON.stringify(request) + "\n");
        }

        onExited: (code, status) => {
            root.ready = false;
            root.known = false;
            root.loading = false;
            root.service = ({});
            if (root.busy) {
                root.closeReply();
                root.busy = false;
                root.phase = "idle";
            }
            if (root.wanted && root.restarts < 5) {
                root.restarts++;
                restart.restart();
            }
        }
    }

    Timer {
        id: restart
        interval: 1500 * root.restarts
        onTriggered: if (root.wanted && !agent.running) agent.running = true
    }

    IpcHandler {
        target: "nilo"

        function toggle(): void { root.toggle(); }
        function open(): void { root.open(); }
        function sleep(): void { root.sleep(); }
        function ask(text: string): void {
            root.open();
            root.ask(text);
        }
    }
}
