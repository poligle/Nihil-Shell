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
        # Not "input": it reads every keyboard and touchpad on the machine,
        # and so would any program the user runs. The microphone's LED, all
        # it was for, has a group of its own (modules/hardware.nix).
        extraGroups = [ "wheel" "networkmanager" "video" "nihil-leds" ];
    };

    users.groups.nihil-leds = { };
}
