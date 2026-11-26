# network.nix by poligle

{ config, lib, pkgs, ... }:
{
    networking.networkmanager.enable = true;
    hardware.bluetooth.enable = true;
    # Bluetooth is off while rfkill blocks it, which is how the shell turns it off. The shell keeps
    # that choice and blocks again when an adapter shows up, since systemd-rfkill can lose it.
    hardware.bluetooth.powerOnBoot = lib.mkDefault true;
    services.blueman.enable = true;
    networking.networkmanager.wifi.powersave = lib.mkDefault false;
}
