# desktop.nix by poligle

{ config, lib, pkgs, ... }:
{
    programs.thunar = {
        enable = true;
        plugins = with pkgs; [
            thunar-archive-plugin
            thunar-volman
        ];
    };
    services.gvfs.enable = true;
    services.tumbler.enable = true;
}
