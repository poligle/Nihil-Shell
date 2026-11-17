# desktop.nix by poligle

{ config, lib, pkgs, ... }:
{
    programs.thunar = 
    {
        enable = lib.mkDefault true;
        plugins = with pkgs; 
        [
            thunar-archive-plugin
            thunar-volman
        ];
    };
    
    services.gvfs.enable = lib.mkDefault true;
    services.tumbler.enable = lib.mkDefault true;
    programs.dconf.enable = lib.mkDefault true;
}