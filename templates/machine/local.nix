# local.nix: NixOS settings of this machine only (drivers, services,
# packages). NIHIL's own are in its flake, settings.json has the rest.

{ config, lib, pkgs, ... }:
{
	# The NixOS release this machine was installed with: keep it as it is.
	system.stateVersion = "26.05";

	# Pictures in /etc/nixos/wallpapers become wallpapers too, drawn as dots.
	nihil.extraWallpapers = lib.optional (builtins.pathExists ./wallpapers) ./wallpapers;
}
