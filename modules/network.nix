# network.nix by poligle

{ config, lib, pkgs, ... }:
{
    networking.networkmanager.enable = true;
    hardware.bluetooth.enable = true;
    services.blueman.enable = true;
    networking.networkmanager.wifi.powersave = false;
}
