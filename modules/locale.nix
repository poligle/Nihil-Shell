# locale.nix by poligle

{ config, lib, pkgs, ... }:
{
    time.timeZone = "Europe/Madrid";
    i18n.defaultLocale = "es_ES.UTF-8";
    console = {
        font = "Lat2-Terminus16";
        useXkbConfig = true;
    };
    services.xserver.xkb.layout = "es";
}
