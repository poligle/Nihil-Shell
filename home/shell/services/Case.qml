pragma Singleton

import Quickshell

// Sentence case, as everywhere in NIHIL: the first letter in capitals, the
// rest as written, proper names their own way. theme/i18n.nix is written
// so; this is for what comes from elsewhere (a weekday from the locale, a
// wallpaper's folder, a player's name) and for keys, as a keyboard names
// them.
Singleton {
    function sentence(text: string): string {
        const s = String(text ?? "");
        return s.length > 0 ? s.charAt(0).toLocaleUpperCase() + s.slice(1) : s;
    }

    // SUPER → Super, CTRL → Ctrl, v → V, space → Space, PRINT → Print;
    // F5, Super_L or code:201 as they are.
    function key(name: string): string {
        const part = String(name ?? "").trim();
        const upper = part.toUpperCase();
        const modifiers = { SUPER: "Super", WIN: "Super", LOGO: "Super", MOD4: "Super", META: "Super",
                            CTRL: "Ctrl", CONTROL: "Ctrl", SHIFT: "Shift", ALT: "Alt", MOD1: "Alt" };
        if (upper in modifiers)
            return modifiers[upper];
        if (part.length === 1 || /^F[0-9]+$/i.test(part))
            return upper;
        if (part.indexOf(":") >= 0)
            return part;
        if (part === upper)
            return part.charAt(0) + part.slice(1).toLowerCase();
        return part.charAt(0).toUpperCase() + part.slice(1);
    }

    // "SUPER + SHIFT + V" → "Super + Shift + V".
    function keys(combo: string): string {
        return String(combo ?? "").split("+").map(part => part.trim()).filter(part => part !== "")
            .map(part => key(part)).join(" + ");
    }
}
