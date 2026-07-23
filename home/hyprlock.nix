# hyprlock.nix by poligle

{ config, pkgs, ... }: {
  	programs.hyprlock = {
    		enable = true;
    		settings = {
      		general = {
       	 		hide_cursor = true;
      		};
      		background = {
        		monitor = "";
        		blur_passes = 2;
        		blur_size = 5;
      		};
      		label = {
        		monitor = "";
        		text = "$TIME";
        		font_size = 90;
        		position = "0, 80";
        		halign = "center";
        		valign = "center";
      		};
      		"input-field" = {
        		monitor = "";
        		size = "200, 50";
        		outline_thickness = 3;
        		dots_size = 0.33;
        		dots_spacing = 0.15;
        		dots_center = true;
        		fade_on_empty = true;
        		placeholder_text = "<i>Ingresa contraseña...</i>";
        		position = "0, -20";
        		halign = "center";
        		valign = "center";
      		};
      		auth = {
        		"fingerprint:enabled" = true;
        		"fingerprint:ready_message" = "Escanea tu huella para desbloquear";
        		"fingerprint:present_message" = "Escaneando...";
      		};
    		};
  	};
}
