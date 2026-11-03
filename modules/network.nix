# network.nix by poligle

{ config, lib, pkgs, ... }:
{
    networking.networkmanager.enable = true;
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = false;
    services.blueman.enable = true;
    networking.networkmanager.wifi.powersave = false;

    # Bluetooth stays off after booting, and blocked if it went down blocked:
    # the panel unblocks it and powers it on (home/shell/services/Bt.qml;
    # systemd's own uaccess rule hands the session /dev/rfkill). Not
    # unblocked here: bluetoothd powers an adapter on as soon as it is.
    systemd.services.bluetooth-off-at-boot = 
    {
        description = "Power off Bluetooth adapter at boot";
        wantedBy = [ "multi-user.target" ];
        after = [ "bluetooth.service" ];
        requires = [ "bluetooth.service" ];
        # At boot only: a rebuild that changes it (Preferences applying
        # anything) must not turn off a Bluetooth in use.
        restartIfChanged = false;
        serviceConfig = 
        {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
            # No adapter yet (its firmware still loading) is no failure.
            ExecStart = "-${pkgs.bluez}/bin/bluetoothctl power off";
        };
    };
}
