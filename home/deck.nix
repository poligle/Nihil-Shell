# deck.nix by poligle
#
# The phone as a deck (nihil.deck.enable, modules/deck.nix; docs/deck.md):
# nihil-deck's service, in the session, so what the phone opens opens here,
# and its command, which Preferences, Devices runs to pair one.
#   systemctl --user status nihil-deck      nihil-deck pair | devices | forget ID

{ config, osConfig, pkgs, lib, ... }:
let
	deck = import ./deck
	{
		inherit pkgs lib osConfig;
		profile = "${config.home.profileDirectory}/bin";
		iconTheme = config.gtk.iconTheme.name;
	};
in
{
	config = lib.mkIf osConfig.nihil.deck.enable
	{
		home.packages = [ deck ];

		systemd.user.services.nihil-deck =
		{
			Unit =
			{
				Description = "NIHIL deck: the phone opens apps and pages here (docs/deck.md)";
				After = [ "graphical-session.target" ];
				PartOf = [ "graphical-session.target" ];
			};

			Service =
			{
				ExecStart = "${deck}/bin/nihil-deck serve";
				Restart = "on-failure";
				RestartSec = 5;
			};

			Install.WantedBy = [ "graphical-session.target" ];
		};
	};
}
