# locale.nix by poligle
#
# Time zone, locale and keyboard come from the machine's settings
# (settings.nix); the console follows the keyboard.

{ config, lib, pkgs, ... }:
{
    console =
    {
        font = "Lat2-Terminus16";
        useXkbConfig = true;
    };
}
