pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.config

// The overview's key held, as the clipboard's (services/Clipboard.qml): the
// first press brings it out on the workspace you are on, each one after
// chooses the next (with SHIFT, the one before), and letting go of its
// modifier goes to the one chosen. Let go before choosing, and it stays out
// for the arrows, Tab, Enter, Escape or a click (drawers/Overview.qml).
//
// Hyprland says the key as a global shortcut (nihil-overview); its modifier
// going down and up, as the clipboard already hears it (nihil-super, or
// nihil-ctrl, nihil-alt, nihil-shift: Clipboard.down). While it is held, a
// submap, nihil-overview (home/hyprland.nix), takes the keys that would
// otherwise move what is behind (SUPER + Tab, SUPER and the arrows) and
// says them as nihil-overview-next, -back, -go and -cancel. The shell enters
// it here, as the overview comes out with the modifier down, and leaves it
// as the modifier goes up (Hyprland leaves it then too); the key's own bind
// can't, as a bind that says a global shortcut runs again on its release,
// and that may come after the modifier's. Without a modifier (a key such as
// F12), there is nothing to hold: the overview simply stays out.
Singleton {
    id: root

    // Out by the key with its modifier down, and not let go yet; chosen
    // another since; the submap entered.
    property bool held: false
    property bool moved: false
    property bool entered: false

    // Its key as the machine has it ("SUPER + A"): the modifier by its
    // shortcut's name ("super"), and the key, which the overview also takes
    // with the keyboard (Qt's code for it).
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

    // drawers/Overview.qml listens: choose by `delta`, or go to the one chosen.
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

    // `gone`: Hyprland left it already (Return or Escape in it).
    function leave(gone: bool): void {
        if (!root.entered)
            return;
        root.entered = false;
        if (!gone)
            root.dispatch('hl.dsp.submap("reset")', "submap reset");
    }

    // The key again (or with SHIFT, `delta` -1). With the modifier down it is
    // held again, even after letting go once.
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
