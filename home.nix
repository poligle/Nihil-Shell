{ config, pkgs, ... }:

{
	home.username = "poligle";
	home.homeDirectory = "/home/poligle";

	home.stateVersion = "26.05";

	programs.home-manager.enable = true;

	programs.kitty = {
		enable = true;
		settings = {
			font_size = 12;
			background_opacity = "0.9";
		};
	};
}
