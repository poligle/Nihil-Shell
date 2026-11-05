# home.nix by poligle
#
# NIHIL for the user of every machine (Home Manager). A machine's own apps
# and settings go in its /etc/nixos/home.nix (templates/machine), not here.

{ config, osConfig, pkgs, lib, inputs, ... }:
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
		./home/zen.nix
		./home/bluetooth.nix
		./home/cli.nix
		./home/refresh.nix
		./home/shell.nix
		./home/fastfetch.nix
	];

	home.username = osConfig.nihil.user.name;
	home.homeDirectory = "/home/${osConfig.nihil.user.name}";
	# The release NIHIL's home started on, for every machine: it stays as it
	# is when NIHIL moves to a newer NixOS. system.stateVersion is each
	# machine's own, in its local.nix.
	home.stateVersion = "26.05";
	programs.home-manager.enable = true;

	# What the shell and its keys open: the audio and network editors, the
	# notifications of the scripts, the wallpaper daemon, screenshots and
	# the colour picker.
	home.packages =
	[
		pkgs.pavucontrol
		pkgs.networkmanagerapplet
		pkgs.libnotify
		pkgs.awww
		pkgs.hyprshot
		pkgs.hyprpicker
	];
}
