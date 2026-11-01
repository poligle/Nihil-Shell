# default.nix by poligle (home/nilo)
#
# Nilo's agent for the shell: agent.py with its configuration, wrapped as
# `nilo-agent`. home/shell.nix hands its path to the shell (Config.nilo);
# the shell starts it the first time Nilo opens and talks to it over
# stdin/stdout. Tests: python3 -m unittest home/nilo/test_agent.py

{ pkgs, lib, osConfig, terminal ? "kitty" }:
let
    nihil = osConfig.nihil;
    ollama = osConfig.services.ollama;

    config = pkgs.writeText "nilo.json" (builtins.toJSON
    {
        ollama = "http://${ollama.host}:${toString ollama.port}";
        inherit (nihil) language;
        inherit (nihil.nilo) models contextLength searxng;
        ddgr = "${pkgs.ddgr}/bin/ddgr";
        git = "${pkgs.git}/bin/git";
        # run_command: bash for what Nilo runs, the terminal for what the user
        # has to see or type into (sudo).
        bash = "${pkgs.bash}/bin/bash";
        inherit terminal;
        host = osConfig.networking.hostName;
        flake = "~/nixos-config";
        # What Nilo knows about the system and its rules (the user's notes
        # and the repository's NILO.md are read where they are).
        context = "${./nilo.md}";
        # To start Ollama when it is down, and say why it won't (modules/nilo.nix).
        systemctl = "${osConfig.systemd.package}/bin/systemctl";
        journalctl = "${osConfig.systemd.package}/bin/journalctl";
        ollamaUnit = "ollama.service";
    });
in
pkgs.writeShellScriptBin "nilo-agent" ''
    exec ${pkgs.python3}/bin/python3 -I ${./agent.py} --config ${config} "$@"
''
