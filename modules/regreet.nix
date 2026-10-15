# regreet.nix by poligle

{ config, lib, pkgs, ... }:
{
    programs.regreet =
    {
        enable = true;
        cageArgs = [ "-s" "-d" "-m" "last" ];

        settings =
        {
            appearance.greeting_msg = "Bienvenido, Pol";

            widget.clock =
            {
                format = "%H:%M";
                resolution = "500ms";
                label_width = 150;
            };
        };
    };

    environment.sessionVariables.XKB_DEFAULT_LAYOUT = config.services.xserver.xkb.layout;
}
