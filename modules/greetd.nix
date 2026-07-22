# greetd.nix by poligle

{ config, lib, pkgs, ... }:
{
    services.greetd = {
        enable = true;
        settings = {
            default_session = {
                command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd 'uwsm start hyprland-uwsm.desktop'";
                user = "greeter";
            };
        };
    };
}
