# direnv.nix by poligle

{ pkgs, ... }:

{

    programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
    };
}
