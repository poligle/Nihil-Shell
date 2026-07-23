# default.nix by poligle (thinkpad)

{ config, lib, pkgs, ... }:
{
    imports = [
        ./hardware-configuration.nix
        ../../modules/boot.nix
        ../../modules/network.nix
        ../../modules/locale.nix
        ../../modules/audio.nix
        ../../modules/hardware.nix
        ../../modules/users.nix
        ../../modules/packages.nix
        ../../modules/hyprland.nix
        ../../modules/greetd.nix
        ../../modules/desktop.nix
        ../../modules/services.nix
        ../../modules/nix.nix
        ../../modules/plymouth.nix
        ../../modules/stylix.nix
    ];

    # Host-specific
    networking.hostName = "thinkpad";
    system.stateVersion = "26.05";
}
