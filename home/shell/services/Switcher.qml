pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.config

Singleton {
    id: root

    property bool held: false
    property bool moved: false
    property bool entered: false

    readonly property var keyParts: String(Config.binds.overview ?? "").split("+").map(part => part.trim()).filter(part => part !== "")
    readonly property string modifier: {
        if (keyParts.length < 2)
            return "";
        const alias = { WIN: "SUPER", LOGO: "SUPER", MOD4: "SUPER", META: "SUPER", CONTROL: "CTRL", MOD1: "ALT" };
        const up = keyParts[0].toUpperCase();
        const name = alias[up] ?? up;
        return ["SUPER", "CTRL", "ALT", "SHIFT"].indexOf(name) >= 0 ? name.toLowerCase() : "";
    }
    readonly property string keyName: keyParts.length > 0 ? keyParts[keyParts.length - 1] : ""
    readonly property int keyCode: {
        if (keyName.length === 1)
            return keyName.toUpperCase().charCodeAt(0);
        const code = Qt["Key_" + keyName];
        return typeof code === "number" ? code : -1;
    }
    readonly property bool modifierDown: root.modifier !== "" && (Clipboard.down[root.modifier] ?? false)
    readonly property bool open: Drawers.current === "overview"

    signal stepped(int delta)
    signal commit()

    function dispatch(lua: string, classic: string): void {
        Hyprland.dispatch(Hyprland.usingLua ? lua : classic);
    }

    function enter(): void {
        if (root.entered || !root.modifierDown)
            return;
        root.entered = true;
        root.dispatch('hl.dsp.submap("nihil-overview")', "submap nihil-overview");
    }

    function leave(gone: bool): void {
        if (!root.entered)
            return;
        root.entered = false;
        if (!gone)
            root.dispatch('hl.dsp.submap("reset")', "submap reset");
    }

    function press(delta: int): void {
        if (!root.open) {
            root.held = root.modifierDown;
            root.moved = false;
            Drawers.open("overview", "", false);
            root.enter();
            return;
        }
        if (root.modifierDown) {
            root.held = true;
            root.enter();
        }
        root.moved = true;
        root.stepped(delta);
    }

    function go(): void {
        root.leave(true);
        root.held = false;
        if (root.open)
            root.commit();
    }

    function cancel(): void {
        root.leave(true);
        root.held = false;
        if (root.open)
            Drawers.close();
    }

    onModifierDownChanged: {
        if (root.modifierDown)
            return;
        root.leave(false);
        if (!root.held)
            return;
        root.held = false;
        if (root.open && root.moved)
            root.commit();
    }

    onOpenChanged: {
        if (root.open)
            return;
        root.leave(false);
        root.held = false;
        root.moved = false;
    }

    GlobalShortcut {
        name: "nihil-overview"
        description: "NIHIL: all the workspaces; held, the next one"
        onPressed: root.press(1)
    }

    GlobalShortcut {
        name: "nihil-overview-next"
        description: "NIHIL: the overview held, the next workspace"
        onPressed: root.press(1)
    }

    GlobalShortcut {
        name: "nihil-overview-back"
        description: "NIHIL: the overview held, the workspace before"
        onPressed: root.press(-1)
    }

    GlobalShortcut {
        name: "nihil-overview-go"
        description: "NIHIL: the overview held, go to the one chosen"
        onPressed: root.go()
    }

    GlobalShortcut {
        name: "nihil-overview-cancel"
        description: "NIHIL: the overview held, leave things as they were"
        onPressed: root.cancel()
    }
}
