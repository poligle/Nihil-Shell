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
        setAsDefaultBrowser = true;
        profiles =
        {
            default =
            {
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
