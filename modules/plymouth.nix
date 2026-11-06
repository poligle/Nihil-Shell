# plymouth.nix by poligle

{ config, lib, pkgs, ... }:
let
  # theme/plymouth.nix: 36 frames switching on and a 60-frame sweep, each
  # frame two ticks of Plymouth's 50 Hz refresh, so 3.84 s to see it whole
  # once, plus what loading the frames takes before it starts.
  splashSeconds = "4.5";
  # With the boot sound, the LEDs wait for it to switch on (1.4 s).
  waitForSound = config.nihil.bootSound;
  litSeconds = "1.5";

  # Since when the splash has been on screen: plymouthd's start (in /proc,
  # in the kernel's 100 Hz ticks) or, if later, the GPU's DRM device
  # appearing, since Plymouth draws nothing until there is one. The rest of
  # splashSeconds, asleep; and with the boot sound, until its LEDs are on:
  # the sound says when they began (/run/nihil/splash-open), or, if it never
  # came, they begin now, in silence.
  splashWait = pkgs.writeShellScript "nihil-splash-wait" ''
    read -r pid 2>/dev/null < /run/plymouth/pid || exit 0
    [ -r "/proc/$pid/stat" ] || exit 0
    read -r -a stat < "/proc/$pid/stat"
    read -r now _ < /proc/uptime
    opened=0
    if ${lib.boolToString waitForSound}; then
      read -r opened _ 2>/dev/null < /run/nihil/splash-open || opened=""
      if [ -z "$opened" ]; then
        ${config.boot.plymouth.package}/bin/plymouth update --status=nihil-open 2>/dev/null || true
        opened=$now
      fi
    fi
    wall=$(${pkgs.coreutils}/bin/date +%s.%N)
    card=$(${pkgs.coreutils}/bin/stat -c %.3Z /dev/dri/card* 2>/dev/null | ${pkgs.coreutils}/bin/sort -n | ${pkgs.coreutils}/bin/tail -n 1)
    left=$(${pkgs.gawk}/bin/awk -v started="''${stat[21]}" -v now="$now" -v wall="$wall" -v card="''${card:-0}" \
      -v want=${splashSeconds} -v opened="$opened" -v lit=${litSeconds} 'BEGIN {
        shown = started / 100
        if (card > 0 && now - (wall - card) > shown) shown = now - (wall - card)
        w = want - (now - shown); if (w > want) w = want
        if (opened > 0 && opened + lit - now > w) w = opened + lit - now
        printf "%.2f", (w > 0 ? w : 0) }')
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
      themePackages = [ (import ../theme/plymouth.nix { inherit pkgs waitForSound; }) ];
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

  # The splash plays whole at least once, both ways. Booting, plymouth-quit
  # ends it (greetd waits for that), so it waits until the splash has been
  # on screen for one whole animation: nothing when the boot is slower,
  # never more than splashSeconds. Shutting down, the splash comes up as
  # the session goes and the machine is off a moment later: the services
  # that show it (ordered before poweroff, reboot…) hold for one animation.
  systemd.services = lib.genAttrs [ "plymouth-poweroff" "plymouth-reboot" "plymouth-halt" "plymouth-kexec" ] (_:
  {
    serviceConfig.ExecStartPost = [ "-${pkgs.coreutils}/bin/sleep ${splashSeconds}" ];
  })
  //
  {
    plymouth-quit.serviceConfig.ExecStartPre = [ "${splashWait}" ];
  };
}
