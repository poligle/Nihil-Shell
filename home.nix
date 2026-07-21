# home.nix by poligle

{ config, pkgs, lib, ... }:
{
  	imports = [
		./home/gtk.nix
		./home/nvim.nix
        ./home/zsh.nix
    	./home/hyprland.nix
    	./home/kitty.nix
		./home/waybar.nix
        ./home/scripts.nix
        ./home/wofi.nix
    	./home/awww.nix
    	./home/hypridle.nix
		./home/hyprlock.nix
		./home/cursortheme.nix
		./home/dunst.nix
  	];

  	home.username = "poligle";
  	home.homeDirectory = "/home/poligle";
  	home.stateVersion = "26.05";
  	programs.home-manager.enable = true;
  	
	home.packages = with pkgs; [
        colloid-icon-theme
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

