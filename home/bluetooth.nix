# bluetooth.nix by poligle
#
# Bluetooth is off when the session starts and the panel's button turns it
# on. Blueman stays for pairing, without its PowerManager and KillSwitch
# plugins: they held the adapter blocked through their own root helper,
# and the button could not turn it on until blueman did.
{ ... }:
{
    dconf.settings."org/blueman/general".plugin-list = [ "!PowerManager" "!KillSwitch" ];
}
