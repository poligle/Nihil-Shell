pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config

// The clipboard history: what was copied, newest first, text and pictures
// (home/clipboard.nix keeps it, with cliphist). Its key (SUPER + V) brings
// it out at the top of the frame with the newest chosen, and the keyboard
// goes to it (drawers/ClipboardView.qml): the key again goes on to the next
// copy, SHIFT back, and letting go of the modifier pastes the one chosen in
// the window that had the keyboard. It goes back on the clipboard, SHIFT +
// Insert reaches that window, and it is the newest again. Enter or a click
// paste too; Escape, a click elsewhere or 20 s without a key leave the
// clipboard as it was. Let go before the history had the keyboard (a quick
// press), it waits for Enter. Hyprland only brings it out: a release bind
// can't see that modifier go up (home/hyprland.nix).
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

    // Its key as the machine has it ("SUPER + V"): the modifier whose
    // release pastes (none for a key without one: then Enter does), and the
    // key, which goes on to the next copy when it reaches the history itself.
    readonly property var keyParts: String(Config.binds.clipboard ?? "").split("+").map(part => part.trim()).filter(part => part !== "")
    readonly property string modifier: keyParts.length > 1 ? keyParts[0].toUpperCase() : ""
    readonly property string keyName: keyParts.length > 0 ? keyParts[keyParts.length - 1] : ""
    // A letter or a digit is its own code in Qt (Qt.Key_V is "V"); others
    // go by name (Space, Insert, F12).
    readonly property int keyCode: {
        if (keyName.length === 1)
            return keyName.toUpperCase().charCodeAt(0);
        const code = Qt["Key_" + keyName];
        return typeof code === "number" ? code : -1;
    }

    // The window to paste in (the one with the keyboard when it came out),
    // and the copy on its way there.
    property var target: null
    property var pending: null

    function open(): void {
        if (!enabled)
            return;
        // Its key again while it is out: Hyprland's bind sends it here.
        if (shown) {
            step(1);
            return;
        }
        target = ToplevelManager.activeToplevel;
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

    // Back on the clipboard, and pasted once the window has the keyboard
    // again (settle, below). Only while it is out: nothing pastes twice.
    function paste(): void {
        if (!shown)
            return;
        idle.stop();
        const item = items[index];
        Drawers.close();
        if (item === undefined)
            return;
        pending = item;
        settle.tries = 0;
        settle.restart();
    }

    function pick(i: int): void {
        index = i;
        paste();
    }

    function cancel(): void {
        idle.stop();
        if (shown)
            Drawers.close();
    }

    // The modifier going up, as Qt names it: SUPER may come as Meta or Hyper.
    function isModifier(key: int): bool {
        switch (modifier) {
        case "SUPER":
        case "WIN":
        case "LOGO":
        case "MOD4":
        case "META":
            return key === Qt.Key_Super_L || key === Qt.Key_Super_R || key === Qt.Key_Meta
                || key === Qt.Key_Hyper_L || key === Qt.Key_Hyper_R;
        case "CTRL":
        case "CONTROL":
            return key === Qt.Key_Control;
        case "ALT":
        case "MOD1":
            return key === Qt.Key_Alt || key === Qt.Key_AltGr;
        case "SHIFT":
            return key === Qt.Key_Shift;
        }
        return false;
    }

    function forget(id: string): void {
        items = items.filter(item => item.id !== id);
        index = Math.min(index, Math.max(0, items.length - 1));
        Quickshell.execDetached([Config.cmd.clipboard, "delete", id]);
        idle.restart();
    }

    function forgetChosen(): void {
        const item = items[index];
        if (item !== undefined)
            forget(item.id);
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

    // Nothing pressed for a while: it goes.
    Timer {
        id: idle
        interval: 20000
        onTriggered: root.cancel()
    }

    // The keyboard goes back to the window as the drawer goes in. The paste
    // waits for it, at least two ticks and at most eight; if by then another
    // window is the active one, the copy only goes back on the clipboard.
    Timer {
        id: settle

        property int tries: 0

        interval: 60
        repeat: true
        onTriggered: {
            tries += 1;
            const active = ToplevelManager.activeToplevel;
            const back = root.target === null || active === root.target;
            if (tries < 2 || (!back && tries < 8))
                return;
            stop();
            const item = root.pending;
            root.pending = null;
            if (item === null)
                return;
            const elsewhere = !back && active !== null;
            Quickshell.execDetached([Config.cmd.clipboard, elsewhere ? "copy" : "paste", item.id, item.mime]);
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
