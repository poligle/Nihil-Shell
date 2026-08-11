# virtualisation.nix by poligle

{ config, pkgs, ... }:
{
    virtualisation.docker.enable = true;

    boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
    boot.binfmt.registrations."aarch64-linux" = {
        fixBinary = true;
    };
}