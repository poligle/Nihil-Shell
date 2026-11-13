# hardware.nix by poligle

{ config, lib, pkgs, ... }:
let
    # When the fingerprint reader is left out and the password asked at
    # once: with the lid closed (the reader is under it), and when the NIHIL
    # shell runs sudo with the password already typed, so no finger is asked
    # after it. That sudo's pid is in the user's nihil-sudo-password
    # (services/Machine.qml), and sudo is pam_exec's parent. And when the
    # password was typed in NIHIL's greeter while the reader waited
    # (greeter/shell.qml): the greeter's nihil-greeter-password, which only
    # it can make. Leaving the reader out never lets anyone in without the
    # password.
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
