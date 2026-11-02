# network.nix by poligle

{ config, lib, pkgs, ... }:
{
    networking.networkmanager.enable = true;
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = false;
    services.blueman.enable = true;
    networking.networkmanager.wifi.powersave = false;

    systemd.services.bluetooth-off-at-boot = 
    {
        description = "Power off Bluetooth adapter at boot";
        wantedBy = [ "multi-user.target" ];
        after = [ "bluetooth.service" ];
        requires = [ "bluetooth.service" ];
        serviceConfig = 
        {
            Type = "oneshot";
            ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
            ExecStart = "${pkgs.bluez}/bin/bluetoothctl power off";
        };
    };
}
