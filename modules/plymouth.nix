# plymouth.nix by poligle

{ config, lib, pkgs, ... }:
{
  boot = {
    plymouth.enable = true;

    # Silent boot
    consoleLogLevel = 3;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "splash"
      "loglevel=3"
      "udev.log_level=3"
      "systemd.show_status=auto"
      "rd.udev.log_level=3"
    ];

    loader.timeout = 3;
  };
}
