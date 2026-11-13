# binds.nix by poligle
#
# The keys and touchpad gestures of the actions NIHIL has, and the programs
# with a key (home/hyprland.nix turns them into binds). Each machine can
# change any of them from its settings.json ("binds", "programs",
# "gestures", through settings.nix) or local.nix: a key combination, or null
# for none. Preferences writes the keys and the programs
# (home/shell/settings/PageKeys.qml); the gestures change only there.
# Workspaces (SUPER + a digit), focus (SUPER + arrows), media keys and the
# mouse stay as they are.

{ config, lib, ... }:
let
    keys =
    {
        launcher = "SUPER + Space";
        dashboard = "SUPER + D";
        panel = "SUPER + P";
        colourPicker = "SUPER + H";
        lock = "SUPER + K";
        nilo = "SUPER + I";
        settings = "SUPER + O";
        wallpapers = "SUPER + W";
        # Copy and paste on the same modifier: SUPER + C copies, SUPER + V
        # pastes, and held down brings out the history (home/hyprland.nix).
        copy = "SUPER + C";
        clipboard = "SUPER + V";
        close = "SUPER + Q";
        float = "SUPER + SHIFT + Space";
        maximize = "SUPER + F";
        fullscreen = "SUPER + SHIFT + F";
        special = "SUPER + Escape";
        toSpecial = "SUPER + Control_L";
        nextWorkspace = "SUPER + Tab";
        # Screenshots (nihil-shot), kept in Pictures and copied: the screen
        # on Print, an area on the snipping key (the one Windows laptops
        # label Snipping Tool, XF86SelectiveScreenshot to Linux).
        screenshot = "PRINT";
        snip = "XF86SelectiveScreenshot";
    };

    # Programs with a key; a machine's settings.json "programs" replaces them.
    programs =
    [
        { name = "Terminal"; exec = "kitty"; keys = "SUPER + Super_L"; }
        { name = config.nihil.strings.bindFiles; exec = "thunar"; keys = "SUPER + E"; }
        { name = "Zen"; exec = "zen-beta"; keys = "SUPER + X"; }
    ];

    # Actions that became programs: a settings.json that still names them is
    # read without them.
    former = [ "terminal" "files" "browser" "notes" "code" "music" "pixels" ];

    # Fingers on the touchpad for each gesture.
    gestures =
    {
        workspaces = 3;     # sideways: the next or previous workspace
        close = 3;          # down: close the window
        launcher = 3;       # up: the launcher
        maximize = 3;       # spread: the window maximised; brought together, back
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
            apply = changed: keys // removeAttrs changed former;
            example = { launcher = "SUPER + R"; screenshot = null; };
            description = "Keys for NIHIL's actions, over the defaults in modules/binds.nix; null for none.";
        };

        bindDefaults = lib.mkOption
        {
            type = lib.types.attrs;
            default = { inherit keys gestures programs; };
            readOnly = true;
            description = "NIHIL's own keys and fingers, before a machine changes them (Preferences shows both).";
        };

        programs = lib.mkOption
        {
            type = lib.types.listOf (lib.types.submodule
            {
                options =
                {
                    name = lib.mkOption { type = lib.types.str; };
                    exec = lib.mkOption { type = lib.types.str; };
                    keys = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
                };
            });
            default = programs;
            description = "Programs with a key: a name, the command that opens it and its keys (Preferences, Shortcuts).";
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
