# deck.nix by poligle
#
# The phone as a deck for this computer (docs/deck.md): NIHIL Launcher, on
# Android, opens apps and web pages here, plays and skips the music, turns
# the volume, locks the screen and is its trackpad. Its service is the
# user's, in the session (home/deck.nix); here, its port in the firewall, its
# name on the local network (mDNS, through Avahi), so the phone finds it
# again when its address changes, and uinput for the trackpad. settings.json's "deck": { "enable": true } turns it on
# (Preferences, Phone).

{ config, lib, pkgs, ... }:
let
    cfg = config.nihil.deck;
in
{
    options.nihil.deck =
    {
        enable = lib.mkOption
        {
            type = lib.types.bool;
            default = false;
            description = "The phone as a deck: NIHIL Launcher, paired from Preferences, opens apps and pages here (docs/deck.md).";
        };

        port = lib.mkOption
        {
            type = lib.types.port;
            # NIHIL on a phone's keypad.
            default = 64445;
            description = "The deck's HTTPS port on the local network.";
        };
    };

    config = lib.mkIf cfg.enable
    {
        networking.firewall.allowedTCPPorts = [ cfg.port ];

        # The trackpad (docs/deck.md): while the phone is one, the deck makes a
        # touchpad here with uinput, as whoever is at the computer may (uaccess,
        # as with Steam's controllers). It is a phone's screen and not the
        # laptop's own, so libinput leaves it on with the lid closed and while
        # typing.
        boot.kernelModules = [ "uinput" ];
        services.udev.packages =
        [
            (pkgs.writeTextFile
            {
                name = "nihil-deck-udev-rules";
                destination = "/etc/udev/rules.d/72-nihil-deck.rules";
                text = ''
                    KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
                    SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="NIHIL deck trackpad", ENV{ID_INPUT_TOUCHPAD_INTEGRATION}="external"
                '';
            })
        ];

        # Its own address too, so the phone can resolve where the service is.
        services.avahi =
        {
            enable = true;
            publish =
            {
                enable = true;
                addresses = true;
            };
            extraServiceFiles.nihil-deck = ''
                <?xml version="1.0" standalone="no"?>
                <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
                <service-group>
                  <name replace-wildcards="yes">%h</name>
                  <service>
                    <type>_nihil-deck._tcp</type>
                    <port>${toString cfg.port}</port>
                    <txt-record>v=1</txt-record>
                  </service>
                </service-group>
            '';
        };
    };
}
