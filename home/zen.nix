# zen.nix by poligle

{ config, lib, pkgs, inputs, ... }:
{
    imports = [ inputs.zen-browser.homeModules.beta ];

    programs.zen-browser =
    {
        enable = true;
        profiles =
        {
            default = { };
        };
    };

    stylix.targets.zen-browser.profileNames = [ "default" ];
}
