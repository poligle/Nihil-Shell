# nihil.nix by poligle
#
# NIHIL options shared by the system (Stylix, fonts) and Home Manager
# (shell, wallpapers, hyprlock), which reads them through osConfig.
# Each host describes its outputs; everything else comes from theme/.

{ config, lib, pkgs, ... }:
let
    cfg = config.nihil;

    outputType = lib.types.submodule
    {
        options =
        {
            width = lib.mkOption
            {
                type = lib.types.ints.positive;
                description = "Logical width in px, after rotation.";
            };
            height = lib.mkOption
            {
                type = lib.types.ints.positive;
                description = "Logical height in px, after rotation.";
            };
            bar = lib.mkOption
            {
                type = lib.types.bool;
                default = true;
                description = "Whether the frame widens into the bar on this output.";
            };
            pitch = lib.mkOption
            {
                type = lib.types.ints.positive;
                default = 9;
                description = "Distance between wallpaper dots in px.";
            };
        };
    };
in
{
    options.nihil =
    {
        tokens = lib.mkOption
        {
            type = lib.types.attrs;
            default = import ../theme/nihil.nix;
            readOnly = true;
            description = "NIHIL design tokens (theme/nihil.nix).";
        };

        outputs = lib.mkOption
        {
            type = lib.types.attrsOf outputType;
            default = { };
            description = "Outputs of this host, keyed by connector name.";
        };

        primaryOutput = lib.mkOption
        {
            type = lib.types.str;
            description = "Output for the desktop widgets and the lock/login backgrounds.";
        };

        wallpaper = lib.mkOption
        {
            type = lib.types.str;
            default = "night";
            description = "Default wallpaper: a file name in wallpapers/ without extension.";
        };

        language = lib.mkOption
        {
            type = lib.types.enum [ "es" "en" ];
            default = "es";
            description = "Language of the shell, lock screen, greeter and script messages (theme/i18n.nix).";
        };

        strings = lib.mkOption
        {
            type = lib.types.attrsOf lib.types.str;
            default = (import ../theme/i18n.nix).${cfg.language};
            defaultText = lib.literalExpression "(import ../theme/i18n.nix).\${config.nihil.language}";
            readOnly = true;
            description = "Strings of the selected language.";
        };

        trayHidden = lib.mkOption
        {
            type = lib.types.listOf lib.types.str;
            default = [ "nm-applet" "blueman" ];
            example = [ "nm-applet" "blueman" "steam" ];
            description = ''
                Tray items the bar leaves out, matched case-insensitively against
                part of each item's id or title. The Wi-Fi and Bluetooth applets
                are hidden because the bar has its own icons for both; they keep
                running for password and pairing prompts.
            '';
        };

        soundPack = lib.mkOption
        {
            type = lib.types.enum [ "nihil" "classic" ];
            default = "nihil";
            description = "Interface sounds: the NIHIL pack (sounds/nihil) or the previous ones (sounds/).";
        };

        sounds = lib.mkOption
        {
            type = lib.types.attrsOf lib.types.path;
            readOnly = true;
            description = "Sound file for each interface event, from the selected pack.";
        };

        wallpapers = lib.mkOption
        {
            type = lib.types.package;
            readOnly = true;
            description = "Dot-matrix renders of every wallpaper for every output.";
        };

        fonts = lib.mkOption
        {
            type = lib.types.package;
            readOnly = true;
            description = "NIHIL font families.";
        };
    };

    config =
    {
        assertions =
        [
            {
                assertion = cfg.outputs ? ${cfg.primaryOutput};
                message = "nihil.primaryOutput must be one of nihil.outputs.";
            }
            {
                assertion = builtins.elem cfg.wallpaper cfg.wallpapers.names;
                message = "nihil.wallpaper must match a file in wallpapers/.";
            }
            {
                assertion = let languages = builtins.attrValues (import ../theme/i18n.nix); in
                    lib.all (strings: builtins.attrNames strings == builtins.attrNames (lib.head languages)) languages;
                message = "theme/i18n.nix: every language needs the same keys.";
            }
        ];

        nihil.wallpapers = import ../theme/wallpapers.nix { inherit pkgs lib; outputs = cfg.outputs; };
        nihil.fonts = import ../theme/fonts.nix { inherit pkgs; };

        nihil.sounds =
            let
                freedesktop = "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo";
                events = [ "switch" "open" "close" "special" "fullscreen" "lock" "power" "menu" "notify" "critical" "volume" ];
            in
            if cfg.soundPack == "nihil" then
                lib.genAttrs events (event: ../sounds/nihil + "/${event}.ogg")
            else
                lib.genAttrs [ "switch" "open" "close" "special" "fullscreen" "lock" "power" "menu" ] (event: ../sounds + "/${event}.ogg")
                // {
                    notify = "${freedesktop}/message.oga";
                    critical = "${freedesktop}/dialog-error.oga";
                    volume = "${freedesktop}/audio-volume-change.oga";
                };

        fonts.packages = [ cfg.fonts ];

        # The shell reads the battery through UPower (D-Bus); waybar used to
        # read /sys directly, so nothing had enabled it before.
        services.upower.enable = lib.mkDefault true;
    };
}
