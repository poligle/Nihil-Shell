# default.nix by poligle (modules)
#
# NIHIL as a NixOS module: the same on every machine. What belongs to one
# machine (who uses it, its screens and keyboard, hardware-configuration.nix,
# its own local.nix and home.nix) comes through nihil.lib.mkSystem (flake.nix).

{ ... }:
{
    imports =
    [
        ./boot.nix
        ./network.nix
        ./locale.nix
        ./audio.nix
        ./hardware.nix
        ./users.nix
        ./packages.nix
        ./hyprland.nix
        ./regreet.nix
        ./desktop.nix
        ./storage.nix
        ./services.nix
        ./nix.nix
        ./plymouth.nix
        ./boot-sound.nix
        ./stylix.nix
        ./direnv.nix
        ./nihil.nix
        ./nihil-cli.nix
        ./binds.nix
    ];
}
