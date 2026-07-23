# firefox.nix by poligle

{ config, pkgs, ... }:
{
    programs.firefox = {
        enable = true;
        profiles.poligle = { };
    };

    stylix.targets.firefox.profileNames = [ "poligle" ];
}
