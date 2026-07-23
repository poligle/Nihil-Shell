# home.nix by poligle

{ config, pkgs, lib, ... }:
{
  	imports = [
		./home/gtk.nix
		./home/nvim.nix
        ./home/zsh.nix
        ./home/thunar.nix
    	./home/hyprland.nix
    	./home/kitty.nix
		./home/waybar.nix
        ./home/scripts.nix
        ./home/wofi.nix
        ./home/desktop-entries.nix
    	./home/awww.nix
    	./home/hypridle.nix
		./home/hyprlock.nix
		./home/dunst.nix
        ./home/python.nix
        ./home/firefox.nix
        ./home/vscode.nix
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
        hyprshot
		hyprpicker

		obsidian
		spotify
		libreoffice
        (octaveFull.withPackages (ps: with ps; [ signal ]))
	];
}

