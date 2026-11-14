# default.nix by poligle (home/nilo)

{ pkgs, lib, osConfig, terminal ? "kitty" }:
let
    nihil = osConfig.nihil;
    ollama = osConfig.services.ollama;

    config = pkgs.writeText "nilo.json" (builtins.toJSON
    {
        ollama = "http://${ollama.host}:${toString ollama.port}";
        inherit (nihil) language;
        inherit (nihil.nilo) models contextLength searxng coauthor;
        ddgr = "${pkgs.ddgr}/bin/ddgr";
        git = "${pkgs.git}/bin/git";
        bash = "${pkgs.bash}/bin/bash";
        inherit terminal;
        host = osConfig.networking.hostName;
        flake = osConfig.nihil.flake;
        context = "${./nilo.md}";
        systemctl = "${osConfig.systemd.package}/bin/systemctl";
        journalctl = "${osConfig.systemd.package}/bin/journalctl";
        ollamaUnit = "ollama.service";
    });
in
pkgs.writeShellScriptBin "nilo-agent" ''
    exec ${pkgs.python3}/bin/python3 -I ${./agent.py} --config ${config} "$@"
''
