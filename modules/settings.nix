# settings.nix by poligle
#
# What changes from one NIHIL machine to another: who uses it, its name,
# language, keyboard, time zone, screens, and whether Nilo runs. It comes
# from the machine's settings.json (/etc/nixos, written by the installer
# and the welcome screen) through nihil.lib.mkSystem, and becomes the
# options below; a machine's local.nix can still set any of them.

{ config, lib, ... }:
let
    s = config.nihil.settings;
    get = path: default: lib.attrByPath path default s;

    firstWord = text: lib.head (lib.splitString " " text);
    outputs = get [ "outputs" ] { };
in
{
    options.nihil =
    {
        settings = lib.mkOption
        {
            type = lib.types.attrs;
            default = { };
            description = "The machine's settings.json, as read by nihil.lib.mkSystem.";
        };

        home = lib.mkOption
        {
            type = lib.types.listOf lib.types.deferredModule;
            default = [ ];
            description = "Home Manager modules of this machine, added to NIHIL's for its user.";
        };

        flake = lib.mkOption
        {
            type = lib.types.str;
            default = "/etc/nixos";
            description = "Where the machine's flake is: nihil rebuild and nihil update use it.";
        };

        user =
        {
            name = lib.mkOption
            {
                type = lib.types.strMatching "[a-z_][a-z0-9_-]*";
                default = get [ "user" "name" ] "nihil";
                description = "The account of the person using this machine.";
            };

            fullName = lib.mkOption
            {
                type = lib.types.str;
                default = get [ "user" "fullName" ] "";
                description = "Their name, as the greeter and the welcome say it.";
            };

            greeting = lib.mkOption
            {
                type = lib.types.str;
                default = if config.nihil.user.fullName != "" then firstWord config.nihil.user.fullName else "";
                description = "The name the greeter uses (the first word of fullName).";
            };
        };

        fingerprint = lib.mkOption
        {
            type = lib.types.bool;
            default = get [ "fingerprint" ] false;
            description = "Fingerprint reader for sudo, polkit and the greeter (fprintd).";
        };
    };

    config =
    {
        networking.hostName = lib.mkDefault (get [ "host" "name" ] "nihil");
        time.timeZone = lib.mkDefault (get [ "timeZone" ] "UTC");
        i18n.defaultLocale = lib.mkDefault (get [ "locale" ] "en_US.UTF-8");

        # NixOS checks the layout against xkeyboard-config: the model only
        # when there is one (it defaults to pc104).
        services.xserver.xkb =
        {
            layout = lib.mkDefault (get [ "keyboard" "layout" ] "us");
            variant = lib.mkDefault (get [ "keyboard" "variant" ] "");
            model = lib.mkIf (get [ "keyboard" "model" ] "" != "") (lib.mkDefault (get [ "keyboard" "model" ] ""));
        };

        services.openssh.enable = lib.mkDefault (get [ "ssh" ] false);

        nihil =
        {
            language = lib.mkDefault (get [ "language" ] "en");
            wallpaper = lib.mkDefault (get [ "wallpaper" ] "night");
            outputs = lib.mkDefault outputs;
            # The laptop's panel if there is one, or the first screen.
            primaryOutput = lib.mkDefault (get [ "primaryOutput" ]
                (let names = builtins.attrNames outputs; panels = lib.filter (lib.hasPrefix "eDP") names; in
                    if panels != [ ] then lib.head panels else if names != [ ] then lib.head names else ""));

            nilo =
            {
                enable = lib.mkDefault (get [ "nilo" "enable" ] false);
                acceleration = lib.mkDefault (get [ "nilo" "acceleration" ] "cpu");
                integratedGpu = lib.mkDefault (get [ "nilo" "integratedGpu" ] false);
            };
        };
    };
}
