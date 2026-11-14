# nix.nix by poligle
{ config, lib, pkgs, ... }:
{
    options.nihil.generations.days = lib.mkOption
    {
        type = lib.types.ints.between 1 3650;
        default = 7;
        description = "How many days generations stay before the weekly clean removes them (settings.json's generations.days).";
    };

    config =
    {
        nix =
        {
            settings.experimental-features = [ "nix-command" "flakes" ];
            settings.auto-optimise-store = true;
            gc =
            {
                automatic = true;
                dates = "weekly";
                options = "--delete-older-than ${toString config.nihil.generations.days}d";
            };
        };

        systemd.timers.nix-gc.timerConfig.Persistent = true;

        programs.nh =
        {
            enable = true;
            flake = config.nihil.flake;
        };
    };
}
