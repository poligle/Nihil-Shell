# stylix.nix by poligle
#
# Stylix applies the NIHIL palette system-wide (GTK, Qt, kitty, Neovim,
# VS Code, Zen, ReGreet, Plymouth). The scheme is fixed and comes from
# theme/nihil.nix; the image is the dot-matrix render of the default
# wallpaper on the primary output.

{ config, lib, pkgs, ... }:
let
    nihil = config.nihil;
    tokens = nihil.tokens;
in
{
    stylix = 
    {
        enable = true;
        image = "${nihil.wallpapers}/${nihil.wallpaper}/${nihil.primaryOutput}.png";
        base16Scheme = tokens.base16;
        polarity = "dark";

        cursor = 
        {
            package = pkgs.bibata-cursors;
            name = "Bibata-Modern-Classic";
            size = 15;
        };

        fonts = 
        {
            monospace = 
            {
                package = pkgs.nerd-fonts.jetbrains-mono;
                name = tokens.fonts.code;
            };
            sansSerif = 
            {
                package = nihil.fonts;
                name = tokens.fonts.sans;
            };
            emoji = 
            {
                package = pkgs.noto-fonts-color-emoji;
                name = "Noto Color Emoji";
            };
            sizes = 
            {
                terminal = 11;
                applications = 11;
                desktop = 10;
                popups = 10;
            };
        };

        opacity = 
        {
            terminal = 0.9;
            popups = 0.8;
        };
    };
}
