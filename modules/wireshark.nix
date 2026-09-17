# wireshark.nix by poligle

{ pkgs, ... }:

{
    programs.wireshark = {
        enable = true;
        package = pkgs.wireshark;
    };
}
