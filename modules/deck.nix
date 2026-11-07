# deck.nix by poligle
#
# The phone as a deck for this computer (docs/deck.md): NIHIL Launcher, on
# Android, opens apps and web pages here, plays and skips the music, turns
# the volume and locks the screen. Its service is the user's, in the session
# (home/deck.nix); here, its port in the firewall and its name on the local
# network (mDNS, through Avahi), so the phone finds it again when its
# address changes. settings.json's "deck": { "enable": true } turns it on
# (Preferences, Phone).

{ config, lib, ... }:
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
