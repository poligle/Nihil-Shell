# fonts.nix by poligle

{ pkgs }:
pkgs.google-fonts.override { fonts = [ "Doto" "SpaceGrotesk" "SpaceMono" ]; }
