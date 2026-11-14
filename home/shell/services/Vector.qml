pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    readonly property bool enabled: Config.deck.enabled
    readonly property string folder: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/nihil/vector/in"
    property var received: ({ id: "" })
    readonly property bool has: (root.received.id ?? "") !== ""
    property string text: ""
    readonly property bool busy: sender.running || actor.running
    property bool dropping: false

    signal lit(string what)
    signal sent(var item)

    function send(source: string): void {
        root.run(["send"].concat(source !== "" ? [source] : []));
    }

    function sendText(value: string): void {
        if (value !== "")
            root.run(["text", value]);
    }

    function run(words: var): void {
        if (!root.enabled || sender.running)
            return;
        sender.command = [Config.deck.command, "vector"].concat(words);
        sender.running = true;
    }

    function act(action: string): void {
        if (!root.enabled || !root.has || actor.running)
            return;
        actor.action = action;
        actor.command = [Config.deck.command, "vector", action];
        actor.running = true;
    }

    function fileUrl(path: string): string {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    function home(path: string): string {
        const mine = Quickshell.env("HOME") ?? "";
        return mine !== "" && path.startsWith(mine + "/") ? "~" + path.slice(mine.length) : path;
    }

    function notify(title: string, body: string, picture: string): void {
        Quickshell.execDetached([Config.cmd.notifySend, "-a", "NIHIL"].concat(
            picture !== "" ? ["-h", "string:image-path:" + root.fileUrl(picture)] : [], [title, body]));
    }

    function answer(text: string): var {
        try {
            return JSON.parse(text);
        } catch (error) {
            return { error: "vector" };
        }
    }

    function failure(error: string): string {
        return {
            big: Lang.vectorBig,
            folder: Lang.vectorFolder,
            empty: Lang.vectorEmpty,
            secret: Lang.vectorSecret
        }[error] ?? Lang.vectorFailed;
    }

    function read(): void {
        try {
            const item = JSON.parse(meta.text());
            item.path = root.folder + "/" + item.name;
            root.received = item;
        } catch (error) {
            root.received = ({ id: "" });
        }
    }

    FileView {
        id: meta
        path: root.enabled ? root.folder + "/.item.json" : ""
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.read()
        onLoadFailed: root.received = ({ id: "" })
    }

    FileView {
        id: preview
        path: root.received.kind === "text" ? root.received.path : ""
        blockLoading: true
        printErrors: false
        onLoaded: root.text = preview.text().slice(0, 600)
        onLoadFailed: root.text = ""
        onPathChanged: if (path === "") root.text = ""
    }

    Process {
        id: sender
        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.answer(text);
                if (result.ok) {
                    const devices = result.devices ?? [];
                    root.notify(devices.length > 0 ? Lang.vectorSent.arg(devices.join(", ")) : Lang.vectorWaiting,
                        result.kind === "text" ? "" : result.name, result.kind === "image" ? result.path : "");
                    root.sent(result);
                    root.lit("sent");
                } else {
                    root.notify(root.failure(result.error), "", "");
                    root.lit("failed");
                }
            }
        }
    }

    Process {
        id: actor

        property string action: ""

        stdout: StdioCollector {
            onStreamFinished: {
                const result = root.answer(text);
                meta.reload();
                root.read();
                if (result.ok) {
                    if (actor.action === "save")
                        root.notify(Lang.vectorSaved, root.home(result.path), result.kind === "image" ? result.path : "");
                    root.lit(actor.action);
                } else {
                    root.notify({ copy: Lang.vectorNoCopy, save: Lang.vectorNoSave, open: Lang.vectorNoOpen }[actor.action]
                        ?? Lang.vectorFailed, "", "");
                    root.lit("failed");
                }
            }
        }
    }

    IpcHandler {
        target: "vector"

        function received(): void {
            meta.reload();
            root.read();
            const item = root.received;
            if (!root.has)
                return;
            if (item.kind === "text") {
                preview.reload();
                root.text = preview.text().slice(0, 600);
            }
            root.lit("received");
            root.notify(Lang.vectorFrom.arg(item.from || Lang.vectorDevice),
                item.kind === "text" ? root.text.split("\n")[0].slice(0, 120) : item.name,
                item.kind === "image" ? item.path : "");
        }
    }
}
