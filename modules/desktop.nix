# desktop.nix by poligle

{ config, lib, pkgs, ... }:
let
    # The plugin only looks for an archive manager's wrapper in its own folder.
    archives = pkgs.thunar-archive-plugin.overrideAttrs (old:
    {
        postInstall = (old.postInstall or "") + ''
            ln -s ${pkgs.xarchiver}/libexec/thunar-archive-plugin/xarchiver.tap $out/libexec/thunar-archive-plugin/
        '';
    });
in
{
    programs.thunar = 
    {
        enable = lib.mkDefault true;
        plugins = with pkgs; 
        [
            archives
            thunar-volman
        ];
    };

    environment.systemPackages = lib.mkIf config.programs.thunar.enable [ pkgs.xarchiver ];
    
    services.gvfs.enable = lib.mkDefault true;
    services.tumbler.enable = lib.mkDefault true;
}