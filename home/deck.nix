# deck.nix by poligle
#
# The phone as a deck (nihil.deck.enable, modules/deck.nix; docs/deck.md):
# nihil-deck's service, in the session, so what the phone opens opens here,
# and its command, which Preferences, Devices runs to pair one.
#   systemctl --user status nihil-deck      nihil-deck pair | devices | forget ID
#   nihil-watch [update | forget]           NIHIL for Wear OS on a watch

{ config, osConfig, pkgs, lib, ... }:
let
	deck = import ./deck
	{
		inherit pkgs lib osConfig;
		profile = "${config.home.profileDirectory}/bin";
		iconTheme = config.gtk.iconTheme.name;
	};
	# NIHIL for Wear OS from here: adb's Wireless debugging found on the
	# network, the latest release checked and installed, and the deck's
	# invitation (deck/watch.sh). Preferences, Devices opens it in a terminal.
	watch = pkgs.writeShellApplication
	{
		name = "nihil-watch";
		runtimeInputs = [ deck pkgs.android-tools pkgs.avahi pkgs.curl pkgs.jq pkgs.gawk pkgs.gnugrep pkgs.coreutils ];
		text = builtins.readFile ./deck/watch.sh;
	};
in
{
	config = lib.mkIf osConfig.nihil.deck.enable
	{
		home.packages = [ deck watch ];

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
