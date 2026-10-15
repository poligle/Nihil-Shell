# bluetooth.nix by poligle

{ ... }:
{
    dconf.settings."org/blueman/plugins/powermanager".auto-power-on = false;
}
