# nix.nix by poligle
{ config, lib, pkgs, ... }:
{
    # Each rebuild is a generation, a whole system to go back to (nihil
    # generations, Preferences, Generations). The weekly clean removes the
    # ones older than this but the one in use, and the one that was in use
    # that many days ago, and then what nothing needs any more.
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
