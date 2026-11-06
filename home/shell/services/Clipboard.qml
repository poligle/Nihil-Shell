pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.config

// Paste and the clipboard history (home/clipboard.nix keeps it, with
// cliphist). Its key, SUPER + V, pastes what was copied last once SUPER is
// let go; held a moment longer, the history comes out at the top of the
// frame with the newest chosen (drawers/ClipboardView.qml): V again, Tab or
// the arrows go through the copies, SHIFT back, and letting go of SUPER
// pastes the one chosen. It goes back on the clipboard and is the newest
// again. Return or a click paste too, Delete forgets one; Escape, or 20 s
// without a key, leave the clipboard as it was. The window keeps the
// keyboard all along, so what was open in it stays open, and the paste
// lands where it was: SHIFT + Insert, which Hyprland sends it
// (nihil-clipboard paste). SUPER + C, copying, is Hyprland's alone.
//
// Hyprland says it all as global shortcuts (home/hyprland.nix): the key
// (nihil-clipboard), its modifier going down and up (nihil-super; or
// nihil-ctrl, nihil-alt, nihil-shift for a key on another modifier), and,
// in a submap while the key's modifier is held, the history's own keys
// (nihil-clipboard-next, -back, -forget, -paste, -cancel). If it never said
// the modifier went down (a key without one), the history takes the
// keyboard instead and the view has the keys. With the history off (0
// copies), the key only pastes.
//   nihil-ipc clipboard open | next | previous | released | paste | cancel
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
    // release pastes, by its shortcut's name ("super"; "" for a key without
    // one), and the key, which goes on to the next copy when it reaches the
    // view itself.
    readonly property var keyParts: String(Config.binds.clipboard ?? "").split("+").map(part => part.trim()).filter(part => part !== "")
    readonly property string modifier: {
        if (keyParts.length < 2)
            return "";
        const alias = { WIN: "SUPER", LOGO: "SUPER", MOD4: "SUPER", META: "SUPER", CONTROL: "CTRL", MOD1: "ALT" };
        const up = keyParts[0].toUpperCase();
        const name = alias[up] ?? up;
        return ["SUPER", "CTRL", "ALT", "SHIFT"].indexOf(name) >= 0 ? name.toLowerCase() : "";
    }
    readonly property string keyName: keyParts.length > 0 ? keyParts[keyParts.length - 1] : ""
    // A letter or a digit is its own code in Qt (Qt.Key_V is "V"); others
    // go by name (Space, Insert, F12).
    readonly property int keyCode: {
        if (keyName.length === 1)
            return keyName.toUpperCase().charCodeAt(0);
        const code = Qt["Key_" + keyName];
        return typeof code === "number" ? code : -1;
    }

    // The modifiers down, as Hyprland says: { super: true }.
    property var down: ({})

    // This time round: "" (none), "held" (the key came with its modifier
    // down, so Hyprland will say when it goes up: letting go pastes what is
    // on the clipboard, and after `wait` ms the history comes out) or "out"
    // (the history is out).
    property string phase: ""
    readonly property int wait: 200
    // This round, the history has the keyboard (frame/Frame.qml): only when
    // its keys can't come from Hyprland, as with a key without a modifier.
    property bool keyboard: false

    // The window to paste in (the one with the keyboard when the key came),
    // and what is on its way there: { item } (null: what is on the
    // clipboard, as it is).
    property var target: null
    property var pending: null

    // The key went down (Hyprland's shortcut, or nihil-ipc).
    function press(): void {
        if (phase !== "") {
            step(1);
            return;
        }
        target = ToplevelManager.activeToplevel;
        index = 0;
        if (enabled)
            refresh();
        if (isDown(modifier)) {
            phase = "held";
            later.restart();
        } else if (enabled) {
            keyboard = true;
            reveal();
        } else {
            // No history, and no release to wait for.
            finish(null);
        }
    }

    // Out it comes (with the history on).
    function reveal(): void {
        later.stop();
        if (!enabled || phase === "out")
            return;
        phase = "out";
        Drawers.open("clipboard", "", false);
        idle.restart();
    }

    function step(by: int): void {
        if (phase === "") {
            press();
            return;
        }
        reveal();
        if (phase !== "out")
            return;
        if (items.length > 0)
            index = (index + by + items.length) % items.length;
        idle.restart();
    }

    function isDown(name: string): bool {
        return name !== "" && root.down[name] === true;
    }

    // Hyprland: a modifier went down or up. (Not "modifierChanged": QML
    // gives that name to the change signal of the property `modifier`, and
    // a function taking it stops the whole file from loading.)
    function track(name: string, isPressed: bool): void {
        const next = Object.assign({}, root.down);
        next[name] = isPressed;
        root.down = next;
        if (!isPressed && name === root.modifier)
            released("hyprland");
    }

    // The modifier went up (`from`: Hyprland, the view if the release
    // reached it, or nihil-ipc). More than one may say so: the first ends
    // the round and the others find nothing to do.
    function released(from: string): void {
        if (phase === "held") {
            console.info("nihil: clipboard: let go (" + from + "), pasting what is on the clipboard");
            finish(null);
        } else if (phase === "out") {
            console.info("nihil: clipboard: let go (" + from + ")");
            paste();
        }
    }

    // The one chosen, while it is out (Return, a click, letting go); before
    // it is, what is on the clipboard.
    function paste(): void {
        if (phase === "held")
            finish(null);
        else if (phase === "out")
            finish(items[index] ?? null);
    }

    function pick(i: int): void {
        index = i;
        paste();
    }

    function cancel(): void {
        end();
    }

    // The round is over: the history goes in, and the keyboard goes back to
    // the window it came from.
    function end(): void {
        phase = "";
        keyboard = false;
        later.stop();
        idle.stop();
        if (shown)
            Drawers.close();
    }

    // Over, and `item` (null: what is on the clipboard) pasted in the window
    // once it has the keyboard again (settle, below).
    function finish(item: var): void {
        end();
        pending = { item: item };
        settle.tries = 0;
        settle.restart();
    }

    // The modifier going up, as Qt names it: SUPER may come as Meta or Hyper.
    function isModifier(key: int): bool {
        switch (modifier) {
        case "super":
            return key === Qt.Key_Super_L || key === Qt.Key_Super_R || key === Qt.Key_Meta
                || key === Qt.Key_Hyper_L || key === Qt.Key_Hyper_R;
        case "ctrl":
            return key === Qt.Key_Control;
        case "alt":
            return key === Qt.Key_Alt || key === Qt.Key_AltGr;
        case "shift":
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

    // Only what can be seen: not before the history is out.
    function forgetChosen(): void {
        const item = items[index];
        if (phase === "out" && item !== undefined)
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

    // Another drawer took its place (from the bar, say): the round is over.
    onShownChanged: {
        if (!shown && phase === "out") {
            phase = "";
            keyboard = false;
            idle.stop();
        }
    }

    // Held a moment: out it comes.
    Timer {
        id: later
        interval: root.wait
        onTriggered: root.reveal()
    }

    // Out with no key for a while: it goes.
    Timer {
        id: idle
        interval: 20000
        onTriggered: root.cancel()
    }

    // The keyboard goes back to the window as the history goes in. The paste
    // waits for it, at least two ticks and at most eight; if by then another
    // window is the active one, a copy chosen only goes back on the
    // clipboard, and what is on it stays as it is.
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
            const job = root.pending;
            root.pending = null;
            if (job === null)
                return;
            const elsewhere = !back && active !== null;
            const item = job.item;
            if (item === null) {
                if (elsewhere) {
                    console.info("nihil: clipboard: another window has the keyboard, nothing pasted");
                    return;
                }
                console.info("nihil: clipboard: pasting what is on the clipboard with SHIFT + Insert");
                Quickshell.execDetached([Config.cmd.clipboard, "keys", "paste"]);
                return;
            }
            console.info("nihil: clipboard: " + (elsewhere ? "copied " + item.id + ", another window has the keyboard"
                                                           : "pasting " + item.id + " with SHIFT + Insert"));
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

    // What Hyprland says (home/hyprland.nix binds these names).
    GlobalShortcut {
        name: "nihil-clipboard"
        description: "NIHIL: paste, or the clipboard history held down"
        onPressed: root.press()
    }

    // The history's keys, while its key's modifier is held.
    GlobalShortcut {
        name: "nihil-clipboard-next"
        description: "NIHIL: the next copy in the clipboard history"
        onPressed: root.step(1)
    }

    GlobalShortcut {
        name: "nihil-clipboard-back"
        description: "NIHIL: the copy before in the clipboard history"
        onPressed: root.step(-1)
    }

    GlobalShortcut {
        name: "nihil-clipboard-forget"
        description: "NIHIL: forget the copy chosen in the clipboard history"
        onPressed: root.forgetChosen()
    }

    GlobalShortcut {
        name: "nihil-clipboard-paste"
        description: "NIHIL: paste the copy chosen in the clipboard history"
        onPressed: root.paste()
    }

    GlobalShortcut {
        name: "nihil-clipboard-cancel"
        description: "NIHIL: leave the clipboard history, pasting nothing"
        onPressed: root.cancel()
    }

    GlobalShortcut {
        name: "nihil-super"
        description: "NIHIL: SUPER down and up, for the clipboard history"
        onPressed: root.track("super", true)
        onReleased: root.track("super", false)
    }

    GlobalShortcut {
        name: "nihil-ctrl"
        description: "NIHIL: CTRL down and up, for the clipboard history"
        onPressed: root.track("ctrl", true)
        onReleased: root.track("ctrl", false)
    }

    GlobalShortcut {
        name: "nihil-alt"
        description: "NIHIL: ALT down and up, for the clipboard history"
        onPressed: root.track("alt", true)
        onReleased: root.track("alt", false)
    }

    GlobalShortcut {
        name: "nihil-shift"
        description: "NIHIL: SHIFT down and up, for the clipboard history"
        onPressed: root.track("shift", true)
        onReleased: root.track("shift", false)
    }

    IpcHandler {
        target: "clipboard"

        function open(): void { root.press(); }
        function next(): void { root.step(1); }
        function previous(): void { root.step(-1); }
        function released(): void { root.released("nihil-ipc"); }
        function paste(): void { root.paste(); }
        function cancel(): void { root.cancel(); }
    }
}
