# nix.nix by poligle

{ config, lib, pkgs, ... }:
{
    nix = {
        settings.experimental-features = [ "nix-command" "flakes" ];
        settings.auto-optimise-store = true;
        gc = {
            automatic = true;
            dates = "weekly";
            options = "--delete-older-than 7d";
        };
    };

    systemd.services.nix-gc = {
        postStart = ''
            ${config.system.build.nixos-rebuild}/bin/nixos-rebuild boot --flake /home/poligle/nixos-config/#thinkpad
        '';
    };
}
