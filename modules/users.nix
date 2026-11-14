# users.nix by poligle

{ config, lib, pkgs, ... }:
let
    user = config.nihil.user;
in
{
    programs.zsh.enable = true;

    users.users.${user.name} =
    {
        isNormalUser = true;
        description = user.fullName;
        shell = pkgs.zsh;
        extraGroups = [ "wheel" "networkmanager" "video" "nihil-leds" ];
    };

    users.groups.nihil-leds = { };
}
