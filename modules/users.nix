# users.nix by poligle

{ config, lib, pkgs, ... }:
{
    users.users.poligle = {
        isNormalUser = true;
        description = "Pol";
        shell = pkgs.zsh;
        extraGroups = [ "wheel" "networkmanager" "video" "input" ];
        packages = with pkgs; [
        tree
        ];
    };
    programs.zsh.enable = true;
}
