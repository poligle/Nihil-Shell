# network.nix by poligle

{ config, lib, pkgs, ... }:
{
    networking.networkmanager.enable = true;
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = false;
    services.blueman.enable = true;
    networking.networkmanager.wifi.powersave = false;

    # The panel unblocks Bluetooth as the user if a key blocked it: the active
    # session gets /dev/rfkill, as it gets the GPU. uaccess has to be tagged
    # before 73-seat-late.rules applies it, so not in extraRules (99-local).
    services.udev.packages =
    [
        (pkgs.writeTextDir "lib/udev/rules.d/70-nihil-rfkill.rules" ''
            KERNEL=="rfkill", SUBSYSTEM=="misc", TAG+="uaccess"
        '')
    ];

    systemd.services.bluetooth-off-at-boot = 
    {
        description = "Power off Bluetooth adapter at boot";
        wantedBy = [ "multi-user.target" ];
        after = [ "bluetooth.service" ];
        requires = [ "bluetooth.service" ];
        serviceConfig = 
        {
            Type = "oneshot";
            # Off, but not blocked: the panel only has to power it on.
            ExecStartPre = [ "${pkgs.coreutils}/bin/sleep 3" "${pkgs.util-linux}/bin/rfkill unblock bluetooth" ];
            ExecStart = "${pkgs.bluez}/bin/bluetoothctl power off";
        };
    };
}
