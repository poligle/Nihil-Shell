# binds.nix by poligle
#
# The keys and touchpad gestures of the actions NIHIL has (home/hyprland.nix
# turns them into binds). Each machine can change any of them from its
# settings.json ("binds", "gestures", through settings.nix) or local.nix:
# a key combination, or null for none. Preferences writes them
# (home/shell/settings).
# Workspaces (SUPER + a digit), focus (SUPER + arrows), media keys and the
# mouse stay as they are.

{ config, lib, ... }:
let
    keys =
    {
        terminal = "SUPER + Super_L";
        launcher = "SUPER + Space";
        dashboard = "SUPER + D";
        panel = "SUPER + P";
        files = "SUPER + E";
        browser = "SUPER + X";
        notes = "SUPER + N";
        code = "SUPER + C";
        music = "SUPER + S";
        pixels = "SUPER + A";
        colourPicker = "SUPER + H";
        lock = "SUPER + K";
        nilo = "SUPER + I";
        settings = "SUPER + O";
        wallpapers = "SUPER + W";
        close = "SUPER + Q";
        float = "SUPER + V";
        maximize = "SUPER + F";
        fullscreen = "SUPER + SHIFT + F";
        special = "SUPER + Escape";
        toSpecial = "SUPER + Control_L";
        nextWorkspace = "SUPER + Tab";
        screenshot = "PRINT";
    };

    # Fingers on the touchpad for each gesture.
    gestures =
    {
        workspaces = 3;     # sideways: the next or previous workspace
        close = 3;          # down: close the window
        launcher = 3;       # up: the launcher
        special = 4;        # up or down: the special workspace
    };
in
{
    options.nihil =
    {
        binds = lib.mkOption
        {
            type = lib.types.attrsOf (lib.types.nullOr lib.types.str);
            default = { };
            apply = changed: keys // changed;
            example = { terminal = "SUPER + Return"; pixels = null; };
            description = "Keys for NIHIL's actions, over the defaults in modules/binds.nix; null for none.";
        };

        bindDefaults = lib.mkOption
        {
            type = lib.types.attrs;
            default = { inherit keys gestures; };
            readOnly = true;
            description = "NIHIL's own keys and fingers, before a machine changes them (Preferences shows both).";
        };

        gestures = lib.mkOption
        {
            type = lib.types.attrsOf (lib.types.nullOr (lib.types.ints.between 2 5));
            default = { };
            apply = changed: gestures // changed;
            example = { close = null; special = 3; };
            description = "Fingers for each touchpad gesture, over the defaults in modules/binds.nix; null for none.";
        };
    };

    config.assertions =
    [
        {
            assertion = lib.all (name: keys ? ${name}) (builtins.attrNames config.nihil.binds);
            message = "nihil.binds: unknown action; the actions are ${lib.concatStringsSep ", " (builtins.attrNames keys)}.";
        }
        {
            assertion = lib.all (name: gestures ? ${name}) (builtins.attrNames config.nihil.gestures);
            message = "nihil.gestures: unknown gesture; the gestures are ${lib.concatStringsSep ", " (builtins.attrNames gestures)}.";
        }
    ];
}
