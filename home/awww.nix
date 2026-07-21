# awww.nix by poligle

{ pkgs, ... }:
{
	systemd.user.services.awww-daemon = {
    		Unit = {
      			Description = "Daemon de fondos de pantalla awww para Wayland";
      			After = [ "graphical-session.target" ];
      			PartOf = [ "graphical-session.target" ];
    		};

    		Service = {
    			ExecStart = "${pkgs.awww}/bin/awww-daemon";
    
    			ExecStartPost = "${pkgs.awww}/bin/awww img ${../wallpapers/wallpaper.jpg}";
      
      			Restart = "on-failure";
    		};

    		Install = {
      			WantedBy = [ "graphical-session.target" ];
    		};
  	};
}

