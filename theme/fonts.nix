# fonts.nix by poligle
#
# NIHIL type, all under the SIL Open Font License 1.1:
#   Doto          dot matrix (clocks, big numbers)
#   Space Grotesk interface text
#   Space Mono    uppercase labels and metadata
# Taken from nixpkgs' google-fonts, filtered to these three families.

{ pkgs }:
pkgs.google-fonts.override { fonts = [ "Doto" "SpaceGrotesk" "SpaceMono" ]; }
