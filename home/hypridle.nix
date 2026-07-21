# hypridle.nix by poligle

{ pkgs, ... }: {
	services.hypridle = {
    		enable = true;
    
    		settings = {
      			general = {
        			lock_cmd = "pidof hyprlock || ${pkgs.hyprlock}/bin/hyprlock";
        			before_sleep_cmd = "loginctl lock-session";
        			after_sleep_cmd = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on";
      			};

      			listener = [
        		{
          			timeout = 150;
          			on-timeout = "${pkgs.brightnessctl}/bin/brightnessctl -s set 10";
          			on-resume = "${pkgs.brightnessctl}/bin/brightnessctl -r";
        		}
        		{
          			timeout = 300;
          			on-timeout = "loginctl lock-session";
        		}
        		{
          			timeout = 1800;
          			on-timeout = "systemctl suspend";
        		}
      			];
    		};
  	};
} 

