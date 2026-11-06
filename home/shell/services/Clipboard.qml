pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// The clipboard history: what was copied, newest first, text and pictures
// (home/clipboard.nix keeps it, with cliphist). Its key (SUPER + V) shows it
// at the top of the frame and goes on to the next copy while the modifier
// stays down; letting the modifier go pastes the one chosen: it goes back
// on the clipboard, SHIFT + Insert reaches the window that has the
// keyboard, and it is the newest again. Escape, or 20 s without a key,
// leaves the clipboard as it was. Hyprland holds those keys while it is out
// (home/hyprland.nix), so it never takes the keyboard.
//   nihil-ipc clipboard open | next | previous | paste | cancel
Singleton {
    id: root

    // { id, kind: "text" | "link" | "colour" | "image", text, format, mime, width, height, file }
    property var items: []
    property int index: 0
    // Out, or about to come out (another drawer from the top goes in first).
    readonly property bool shown: Drawers.current === "clipboard" || Drawers.waiting?.name === "clipboard"
    readonly property bool enabled: Config.clipboard > 0
    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nihil-clipboard"

    // Its key as the machine has it, for the hint: "SUPER" and "V".
    readonly property var keyParts: String(Config.binds.clipboard ?? "").split("+").map(part => part.trim()).filter(part => part !== "")
    readonly property string hint: keyParts.length > 1 ? Lang.clipHint.arg(keyParts[0]).arg(keyParts[keyParts.length - 1]) : ""

    function open(): void {
        if (!enabled)
            return;
        index = 0;
        refresh();
        Drawers.open("clipboard", "", false);
        idle.restart();
    }

    function step(by: int): void {
        if (!shown) {
            open();
            return;
        }
        if (items.length > 0)
            index = (index + by + items.length) % items.length;
        idle.restart();
    }

    // Back on the clipboard and pasted where the keyboard is. Only while it
    // is out: a release that comes after a click pastes nothing twice.
    function paste(): void {
        if (!shown)
            return;
        idle.stop();
        const item = items[index];
        Drawers.close();
        if (item)
            Quickshell.execDetached([Config.cmd.clipboard, "paste", item.id, item.mime]);
    }

    // A click: that one, and the keys Hyprland held go back to normal.
    function pick(i: int): void {
        index = i;
        paste();
        release();
    }

    function cancel(): void {
        idle.stop();
        if (shown)
            Drawers.close();
    }

    // The keys Hyprland held, back to the usual ones: it calls them
    // "reset" (there is no submap named "default"). With a Lua
    // configuration hyprctl takes the call as Lua, through eval.
    function release(): void {
        Quickshell.execDetached([Config.cmd.hyprctl, "eval", "hl.dispatch(hl.dsp.submap(\"reset\"))"]);
    }

    function forget(id: string): void {
        items = items.filter(item => item.id !== id);
        index = Math.min(index, Math.max(0, items.length - 1));
        Quickshell.execDetached([Config.cmd.clipboard, "delete", id]);
    }

    function wipe(): void {
        items = [];
        Quickshell.execDetached([Config.cmd.clipboard, "wipe"]);
    }

    function refresh(): void {
        if (!lister.running)
            lister.running = true;
    }

    // cliphist's lines: "<id>\t<preview>"; a picture's preview is
    // "[[ binary data 12 KiB png 640x480 ]]" (the size may be missing).
    function parse(text: string): var {
        const found = [];
        for (const line of text.split("\n")) {
            const tab = line.indexOf("\t");
            if (tab <= 0)
                continue;
            const id = line.slice(0, tab), preview = line.slice(tab + 1);
            const picture = /^\[\[ binary data .* ([a-z]+)(?: (\d+)x(\d+))? \]\]$/.exec(preview);
            if (picture) {
                found.push({ id: id, kind: "image", text: "", format: picture[1], mime: "image/" + picture[1],
                             width: Number(picture[2] ?? 0), height: Number(picture[3] ?? 0),
                             file: root.dir + "/" + id + "." + picture[1] });
            } else {
                const plain = preview.trim();
                const kind = /^#[0-9a-fA-F]{6}$/.test(plain) ? "colour" : /^https?:\/\/\S+$/.test(plain) ? "link" : "text";
                found.push({ id: id, kind: kind, text: preview, format: "", mime: "", width: 0, height: 0, file: "" });
            }
        }
        return found.slice(0, Config.clipboard);
    }

    // Nothing pressed for a while: it goes, and so does the submap.
    Timer {
        id: idle
        interval: 20000
        onTriggered: {
            root.cancel();
            root.release();
        }
    }

    Process {
        id: lister
        command: [Config.cmd.clipboard, "list", String(Config.clipboard)]
        stdout: StdioCollector {
            onStreamFinished: {
                root.items = root.parse(text);
                root.index = Math.min(root.index, Math.max(0, root.items.length - 1));
            }
        }
    }

    IpcHandler {
        target: "clipboard"

        function open(): void { root.open(); }
        function next(): void { root.step(1); }
        function previous(): void { root.step(-1); }
        function paste(): void { root.paste(); }
        function cancel(): void { root.cancel(); }
    }
}
