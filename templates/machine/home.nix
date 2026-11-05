# home.nix: Home Manager settings of this machine's user, on top of
# NIHIL's, which installs little beyond Zen. This machine's apps go here,
# and anything else for its user. For instance, two apps and a mouse a
# little slower:
#
#   home.packages = [ pkgs.spotify pkgs.obsidian ];
#
#   wayland.windowManager.hyprland.settings.device =
#   [
#       { name = "logitech-pro-x-1"; sensitivity = -0.2; }
#   ];

{ config, lib, pkgs, ... }:
{
}
