# stylix.nix by poligle

{ config, lib, pkgs, ... }:
{
    stylix = {
        enable = true;
        image = ../wallpapers/space.jpg;
        polarity = "either";

        cursor = {
            package = pkgs.bibata-cursors;
            name = "Bibata-Modern-Classic";
            size = 15;
        };

        fonts = {
            monospace = {
                package = pkgs.nerd-fonts.jetbrains-mono;
                name = "JetBrainsMono Nerd Font";
            };
            sansSerif = {
                package = pkgs.nerd-fonts.jetbrains-mono;
                name = "JetBrainsMono Nerd Font";
            };
            emoji = {
                package = pkgs.noto-fonts-color-emoji;
                name = "Noto Color Emoji";
            };
            sizes = {
                terminal = 11;
                applications = 11;
                desktop = 10;
                popups = 10;
            };
        };

        opacity = {
            terminal = 0.9;
            popups = 0.8;
        };
    };
}
