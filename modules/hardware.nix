# hardware.nix by poligle

{ config, lib, pkgs, ... }:
let
    lidClosed = pkgs.writeShellScript "lid-closed" ''
        for state in /proc/acpi/button/lid/*/state; do
            [ -r "$state" ] || continue
            ${pkgs.gnugrep}/bin/grep -q closed "$state" && exit 0
        done
        exit 1
    '';

    skipFingerprintWhenLidClosed = service:
    {
        rules.auth.lidClosed =
        {
            enable = config.security.pam.services.${service}.fprintAuth;
            order = config.security.pam.services.${service}.rules.auth.fprintd.order - 1;
            control = "[success=1 default=ignore]";
            modulePath = "${config.security.pam.package}/lib/security/pam_exec.so";
            args = [ "quiet" "${lidClosed}" ];
        };
    };
in
{
    services.libinput.enable = true;
    services.logind.settings.Login = {
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";
        HandleLidSwitchDocked = "ignore";
    };
    services.fprintd.enable = true;
    security.pam.services = lib.genAttrs [ "sudo" "su" "login" "polkit-1" "greetd" ] skipFingerprintWhenLidClosed //
    {
        hyprlock.fprintAuth = false;
    };
    zramSwap.enable = true;
    hardware.graphics.enable = true;
    
    services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="leds", KERNEL=="platform::micmute", RUN+="${pkgs.coreutils}/bin/chgrp input /sys/class/leds/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
    '';
}
