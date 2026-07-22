# packages.nix by poligle

{ config, lib, pkgs, ... }:
{
    programs.firefox.enable = true;

    environment.systemPackages = with pkgs; [
        wev
        wget
        git
        lxqt.lxqt-policykit
        fastfetch
        brightnessctl
        playerctl
    ];

    nixpkgs.config.allowUnfree = true;

    fonts.packages = with pkgs; [
        nerd-fonts.jetbrains-mono
        nerd-fonts.hack
    ];
}
