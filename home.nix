# home.nix by poligle

{ config, pkgs, lib, ... }:
{
  	imports = [
    		./home/hyprland.nix
    		./home/kitty.nix
    		./home/waybar.nix
    		./home/awww.nix
    		./home/hypridle.nix
    		./home/hyprlock.nix
  	];

  	home.username = "poligle";
  	home.homeDirectory = "/home/poligle";
  	home.stateVersion = "26.05";
  	programs.home-manager.enable = true;

	services.dunst = {
    		enable = true;
  	};

  	
	home.packages = with pkgs; [
    		wofi
    		pavucontrol
    		networkmanagerapplet
    		libnotify
		awww
		obsidian
		spotify
		vscode
		hyprshot
		hyprpicker
	];
}

