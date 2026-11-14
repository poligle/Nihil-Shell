# hardware.nix by poligle

{ config, lib, pkgs, ... }:
let
    greeter = config.services.greetd.settings.default_session.user;
    skipReader = pkgs.writeShellScript "skip-fingerprint" ''
        for state in /proc/acpi/button/lid/*/state; do
            [ -r "$state" ] || continue
            ${pkgs.gnugrep}/bin/grep -q closed "$state" && exit 0
        done
        if [ "''${PAM_SERVICE:-}" = sudo ] && uid=$(${pkgs.coreutils}/bin/id -u -- "''${PAM_USER:-}" 2> /dev/null) \
            && [ "$(${pkgs.coreutils}/bin/cat "/run/user/$uid/nihil-sudo-password" 2> /dev/null)" = "$PPID" ]; then
            exit 0
        fi
        if [ "''${PAM_SERVICE:-}" = greetd ] && uid=$(${pkgs.coreutils}/bin/id -u -- ${greeter} 2> /dev/null) \
            && [ -e "/run/user/$uid/nihil-greeter-password" ]; then
            exit 0
        fi
        exit 1
    '';

    skipFingerprint = service:
    {
        rules.auth.skipFingerprint =
        {
            enable = config.security.pam.services.${service}.fprintAuth;
            order = config.security.pam.services.${service}.rules.auth.fprintd.order - 1;
            control = "[success=1 default=ignore]";
            modulePath = "${config.security.pam.package}/lib/security/pam_exec.so";
            args = [ "quiet" "${skipReader}" ];
        };
    };
in
{
    services.libinput.enable = true;

    services.logind.settings.Login =
    {
        HandleLidSwitch = lib.mkDefault "suspend";
        HandleLidSwitchExternalPower = lib.mkDefault "suspend";
        HandleLidSwitchDocked = lib.mkDefault "ignore";
    };
    services.fprintd.enable = config.nihil.fingerprint;

    hardware.enableRedistributableFirmware = lib.mkDefault true;
    boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
    security.pam.services = lib.genAttrs [ "sudo" "su" "login" "polkit-1" "greetd" ] skipFingerprint //
    {
        hyprlock.fprintAuth = false;
    };
    zramSwap.enable = true;
    hardware.graphics.enable = true;
    
    services.udev.extraRules = ''
        ACTION=="add", SUBSYSTEM=="leds", KERNEL=="platform::micmute", RUN+="${pkgs.coreutils}/bin/chgrp nihil-leds /sys/class/leds/%k/brightness", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys/class/leds/%k/brightness"
    '';
}
