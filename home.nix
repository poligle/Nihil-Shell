# home.nix by poligle

{ config, pkgs, lib, inputs, ... }:
{
	imports = 
	[
		./home/gtk.nix
		./home/nvim.nix
        ./home/zsh.nix
        ./home/thunar.nix
		./home/hyprland.nix
		./home/kitty.nix
        ./home/scripts.nix
        ./home/desktop-entries.nix
		./home/wallpaper.nix
		./home/hypridle.nix
		./home/hyprlock.nix
        ./home/python.nix
        ./home/zen.nix
        ./home/vscode.nix
		./home/bluetooth.nix
		./home/engineering.nix
		./home/cli.nix
		./home/refresh.nix
		./home/shell.nix
		./home/fastfetch.nix
	];

	home.username = "poligle";
	home.homeDirectory = "/home/poligle";
	home.stateVersion = "26.05";
	programs.home-manager.enable = true;

	home.packages = 
	[
		pkgs.pavucontrol
		pkgs.networkmanagerapplet
		pkgs.libnotify
		pkgs.awww
        pkgs.hyprshot
		pkgs.hyprpicker

		pkgs.obsidian
		pkgs.spotify
		pkgs.libreoffice
        pkgs.kicad
        (pkgs.octaveFull.withPackages (ps: with ps; [ signal ]))
    ];
}
