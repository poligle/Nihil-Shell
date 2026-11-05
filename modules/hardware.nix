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

    # Closing the lid suspends the laptop, on the charger too, and hypridle
    # locks it first. With another screen connected logind counts it as
    # docked and leaves it awake: Hyprland turns the laptop's panel off and
    # the session goes on on the other screen (home/hyprland.nix). Caffeine
    # only holds the idle timers, never the lid. A machine's local.nix can
    # set any of the three ("lock", "ignore"…).
    services.logind.settings.Login =
    {
        HandleLidSwitch = lib.mkDefault "suspend";
        HandleLidSwitchExternalPower = lib.mkDefault "suspend";
        HandleLidSwitchDocked = lib.mkDefault "ignore";
    };
    services.fprintd.enable = config.nihil.fingerprint;

    # Most Wi-Fi and Bluetooth cards and GPUs need linux-firmware, and new ones
    # a recent kernel: the same the installer boots with.
    hardware.enableRedistributableFirmware = lib.mkDefault true;
    boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
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
