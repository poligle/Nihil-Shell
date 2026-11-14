# deck.nix by poligle

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
            default = 64445;
            description = "The deck's HTTPS port on the local network.";
        };
    };

    config = lib.mkIf cfg.enable
    {
        networking.firewall.allowedTCPPorts = [ cfg.port ];

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
