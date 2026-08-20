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
		./home/waybar.nix
        ./home/scripts.nix
        ./home/wofi.nix
        ./home/desktop-entries.nix
		./home/awww.nix
		./home/hypridle.nix
		./home/hyprlock.nix
		./home/dunst.nix
        ./home/python.nix
        ./home/vscode.nix
	];

	home.username = "poligle";
	home.homeDirectory = "/home/poligle";
	home.stateVersion = "26.05";
	programs.home-manager.enable = true;

	home.packages = 
	[
        pkgs.colloid-icon-theme
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

        inputs.zen-browser.packages."${pkgs.system}".default
    ];
}
