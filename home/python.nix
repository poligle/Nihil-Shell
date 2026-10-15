# python.nix by poligle

{ pkgs, ... }:

let
    pythonfortelecos = pkgs.python3.withPackages (ps: with ps; [
        numpy
        scipy
        matplotlib
        scikit-rf
    ]);
in
{
    home.packages = [
        pythonfortelecos
    ];
}