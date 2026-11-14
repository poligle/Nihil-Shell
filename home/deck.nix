# deck.nix by poligle

{ config, osConfig, pkgs, lib, ... }:
let
	deck = import ./deck
	{
		inherit pkgs lib osConfig;
		profile = "${config.home.profileDirectory}/bin";
		iconTheme = config.gtk.iconTheme.name;
	};
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
