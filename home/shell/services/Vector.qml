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
    readonly property bool busy: sender.running

    signal lit(string what)

    function send(source: string): void {
        if (!root.enabled || sender.running)
            return;
        sender.command = [Config.deck.command, "vector", "send"].concat(source !== "" ? [source] : []);
        sender.running = true;
    }

    function copy(): void {
        if (root.enabled && root.has && !copier.running)
            copier.running = true;
    }

    function notify(title: string, body: string, icon: string): void {
        Quickshell.execDetached([Config.cmd.notifySend, "-a", "NIHIL"].concat(icon !== "" ? ["-i", icon] : [], [title, body]));
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
                let result = {};
                try {
                    result = JSON.parse(text);
                } catch (error) {
                    result = { error: "vector" };
                }
                if (result.ok) {
                    const devices = result.devices ?? [];
                    root.notify(devices.length > 0 ? Lang.vectorSent.arg(devices.join(", ")) : Lang.vectorWaiting,
                        result.kind === "text" ? "" : result.name ?? "", "");
                    root.lit("sent");
                } else {
                    root.notify(result.error === "big" ? Lang.vectorBig : result.error === "folder" ? Lang.vectorFolder
                        : result.error === "empty" ? Lang.vectorEmpty : Lang.vectorFailed, "", "");
                    root.lit("failed");
                }
            }
        }
    }

    Process {
        id: copier
        command: [Config.deck.command, "vector", "copy"]
        onExited: (code, status) => root.lit(code === 0 ? "copied" : "failed")
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
