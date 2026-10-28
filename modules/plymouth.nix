# plymouth.nix by poligle

{ config, lib, pkgs, ... }:
{
  boot = 
  {
    plymouth =
    {
      enable = true;

      # NIHIL splash (theme/plymouth.nix) instead of Stylix's spinning logo.
      theme = "nihil";
      themePackages = [ (import ../theme/plymouth.nix { inherit pkgs; }) ];
    };

    # Silent boot
    consoleLogLevel = 3;
    initrd.verbose = false;
    kernelParams = 
    [
      "quiet"
      "splash"
      "loglevel=3"
      "udev.log_level=3"
      "systemd.show_status=auto"
      "rd.udev.log_level=3"
    ];

    loader.timeout = 5;
  };

  stylix.targets.plymouth.enable = false;
}
