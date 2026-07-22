# vscode.nix by poligle

{ pkgs, ... }:

{
    programs.vscode = {
        enable = true;
        package = pkgs.vscode.fhs;

        profiles.default.extensions = with pkgs.vscode-extensions; [
            ms-python.python
            ms-toolsai.jupyter
        ];

        profiles.default.userSettings = {
            "python.defaultInterpreterPath" = "~/.nix-profile/bin/python";
        };
    };
}

