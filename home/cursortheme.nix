# cursortheme.nix by poligle

{ config, pkgs, lib, ... }:
{
	home.pointerCursor = {
		gtk.enable = true;
		name = "Bibata-Modern-Classic";
		package = pkgs.bibata-cursors;
		size = 10;
	};
}
