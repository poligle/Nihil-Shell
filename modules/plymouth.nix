# plymouth.nix by poligle

{ config, lib, pkgs, ... }:
let
  # theme/plymouth.nix: 36 frames switching on and a 60-frame sweep, each
  # frame two ticks of Plymouth's 50 Hz refresh, so 3.84 s to see it whole
  # once, plus what loading the frames takes before it starts.
  splashSeconds = "4.5";

  # How long plymouthd has been up (its start in /proc, in the kernel's
  # 100 Hz ticks), and the rest of splashSeconds asleep.
  splashWait = pkgs.writeShellScript "nihil-splash-wait" ''
    read -r pid 2>/dev/null < /run/plymouth/pid || exit 0
    [ -r "/proc/$pid/stat" ] || exit 0
    read -r -a stat < "/proc/$pid/stat"
    read -r now _ < /proc/uptime
    left=$(${pkgs.gawk}/bin/awk -v started="''${stat[21]}" -v now="$now" -v want=${splashSeconds} \
      'BEGIN { w = want - (now - started / 100); if (w > want) w = want; printf "%.2f", (w > 0 ? w : 0) }')
    exec ${pkgs.coreutils}/bin/sleep "$left"
  '';
in
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

  # A fast boot reached the login screen before the splash had played
  # once. plymouth-quit ends the splash (greetd waits for it), so it waits
  # until the splash has been up for one whole animation: nothing when the
  # boot is slower than that, never more than splashSeconds.
  systemd.services.plymouth-quit.serviceConfig.ExecStartPre = [ "${splashWait}" ];
}
