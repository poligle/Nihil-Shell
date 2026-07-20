# awww.nix by poligle
{ pkgs, ... }:
{
  
  home.packages = [ pkgs.awww ];

  systemd.user.services.awww-daemon = {
    Unit = {
      Description = "Daemon de fondos de pantalla awww para Wayland";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${pkgs.awww}/bin/awww-daemon";
      Restart = "on-failure";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
