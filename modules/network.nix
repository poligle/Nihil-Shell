# network.nix by poligle

{ config, lib, pkgs, ... }:
{
    networking.networkmanager.enable = true;
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = false;
    services.blueman.enable = true;
    networking.networkmanager.wifi.powersave = false;

    systemd.services.bluetooth-remember =
    {
        description = "Leave Bluetooth as it was at shutdown";
        wantedBy = [ "multi-user.target" ];
        after = [ "bluetooth.service" ];
        requires = [ "bluetooth.service" ];
        restartIfChanged = false;
        path = [ pkgs.bluez pkgs.util-linux pkgs.coreutils ];
        serviceConfig =
        {
            Type = "oneshot";
            RemainAfterExit = true;
            StateDirectory = "nihil/bluetooth";
            ExecStart = pkgs.writeShellScript "bluetooth-restore" ''
                state=$(cat /var/lib/nihil/bluetooth/power 2> /dev/null) || exit 0
                for _ in $(seq 20); do
                    case $(bluetoothctl show 2> /dev/null) in *Controller*) break ;; esac
                    sleep 0.5
                done
                if [ "$state" = on ]; then
                    rfkill unblock bluetooth
                    bluetoothctl power on > /dev/null || true
                else
                    bluetoothctl power off > /dev/null || true
                fi
            '';
            ExecStop = pkgs.writeShellScript "bluetooth-save" ''
                case $(bluetoothctl show 2> /dev/null) in
                    *Controller*"Powered: yes"*) echo on > /var/lib/nihil/bluetooth/power ;;
                    *Controller*) echo off > /var/lib/nihil/bluetooth/power ;;
                esac
            '';
        };
    };
}
