# hardware.nix by poligle

{ config, lib, pkgs, ... }:
{
    services.libinput.enable = true;
    services.fprintd.enable = true;
    security.pam.services.hyprlock.fprintAuth = true;
    zramSwap.enable = true;
    hardware.graphics.enable = true;

    # Allow LED change (micmute)
    services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="leds", KERNEL=="platform::micmute", RUN+="${pkgs.coreutils}/bin/chgrp input /sys/class/leds/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
    '';
}
