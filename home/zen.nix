# zen.nix by poligle

{ config, lib, pkgs, inputs, ... }:
let
    colors = config.lib.stylix.colors.withHashtag;
in
{
    imports = [ inputs.zen-browser.homeModules.beta ];

    programs.zen-browser =
    {
        enable = true;
        profiles =
        {
            default =
            {
                # Selected text, Zen's own. It would take GTK's, a wash of white
                # (home/gtk.nix), on web pages too, where a white page hides it.
                # Ink on a mid grey shows on light pages and dark ones alike
                # (Firefox's system colours for the selection: ui.highlight and
                # ui.highlighttext).
                settings =
                {
                    "ui.highlight" = colors.base03;
                    "ui.highlighttext" = colors.base06;
                };
            };
        };
    };

    stylix.targets.zen-browser.profileNames = [ "default" ];
}
