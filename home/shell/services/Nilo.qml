pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Nilo, the assistant: the shell's side of home/nilo/agent.py. The agent
// starts the first time Nilo opens and stays (it holds the conversation and
// any download); it speaks one JSON object per line. The model itself lives
// in Ollama and goes to sleep on its own after `settings.keepAlive` minutes.
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
    property real ramGB: 0
    property bool ollama: true

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

    // --- Requests ---------------------------------------------------------------

    function ask(text: string): void {
        const question = text.trim();
        if (!question || busy) return;
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
        pull = { model: tag, status: "starting", progress: 0, error: "" };
        send({ op: "pull", model: tag });
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

    function catalogue(e: var): void {
        models = e.models ?? [];
        recommended = e.recommended ?? "";
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
            loaded = e.loaded;
            loading = e.loading;
            expires = e.expires ?? 0;
            sizeGB = e.sizeGB ?? 0;
            gpu = e.gpu ?? 0;
            if (e.ollama !== null && e.ollama !== undefined) ollama = e.ollama;
            break;
        case "reset":
            break;
        case "start":
            busy = true;
            phase = "waiting";
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
                    messages.set(i, { done: true, status: e.ok ? "done" : "failed",
                                      info: JSON.stringify(Object.assign({}, e, { args: args })) });
                }
                if (e.name === "git_commit" && e.ok && !e.declined) mood = "happy";
                phase = "waiting";
                tool = "";
            }
            break;
        case "confirm":
            confirm = e;
            messages.append({ kind: "confirm", text: "", done: false, name: e.action, status: "asking",
                              info: JSON.stringify(e), cid: e.id });
            phase = "confirm";
            break;
        case "confirmed": {
            const i = findTool(e.id);
            if (i >= 0) messages.set(i, { done: true, status: e.ok ? "ok" : "declined" });
            confirm = null;
            phase = "tool";
            break;
        }
        case "done": {
            closeReply();
            const l = last();
            if (e.cancelled)
                messages.append({ kind: "note", text: "", done: true, name: "stopped", status: "", info: "", cid: "" });
            else if (l && l.kind === "nilo" && e.stats && e.stats.tokens)
                messages.setProperty(messages.count - 1, "info", JSON.stringify(e.stats));
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
                pull = e.status === "error" ? { model: e.model, status: "error", progress: 0, error: e.detail ?? "" } : null;
            } else {
                pull = { model: e.model, status: e.status, error: "",
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
