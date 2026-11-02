# users.nix by poligle

{ config, lib, pkgs, ... }:
let
    user = config.nihil.user;
in
{
    programs.zsh.enable = true;

    # The password is not declared here: the installer sets it, and passwd
    # changes it (users.mutableUsers stays on).
    users.users.${user.name} =
    {
        isNormalUser = true;
        description = user.fullName;
        shell = pkgs.zsh;
        extraGroups = [ "wheel" "networkmanager" "video" "input" ];
    };
}
