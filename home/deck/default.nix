# default.nix by poligle (home/deck)
#
# The deck's service and command, `nihil-deck` (deck.py, docs/deck.md),
# with its configuration: the port, the computer's name, and what it runs
# for the phone, by store path or from the user's profile (the shell through
# nihil-ipc, which also locks, the volume as its keys turn it, and the
# clipboard, with wl-clipboard).
# home/deck.nix runs the service; the shell runs the command to pair a device
# and list them (Config.deck). Tests: python3 -m unittest home/deck/test_deck.py

{ pkgs, lib, osConfig, profile, iconTheme }:
let
    nihil = osConfig.nihil;

    config = pkgs.writeText "nihil-deck.json" (builtins.toJSON
    {
        inherit (nihil.deck) port;
        inherit iconTheme;
        name = osConfig.networking.hostName;
        strings = { inherit (nihil.strings) deckPaired deckPairedBody; };
        ipc = "${profile}/nihil-ipc";
        volume = "${profile}/osd-volume";
        notify = lib.getExe' pkgs.libnotify "notify-send";
        openssl = lib.getExe' pkgs.openssl "openssl";
        qrencode = lib.getExe' pkgs.qrencode "qrencode";
        rsvg = lib.getExe' pkgs.librsvg "rsvg-convert";
        ip = lib.getExe' pkgs.iproute2 "ip";
        wpctl = lib.getExe' pkgs.wireplumber "wpctl";
        wlCopy = lib.getExe' pkgs.wl-clipboard "wl-copy";
        wlPaste = lib.getExe' pkgs.wl-clipboard "wl-paste";
    });
in
pkgs.writeShellScriptBin "nihil-deck" ''
    exec ${pkgs.python3}/bin/python3 -I ${./deck.py} --config ${config} "$@"
''
