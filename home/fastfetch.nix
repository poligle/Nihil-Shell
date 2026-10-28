# fastfetch.nix by poligle
#
# fastfetch in the NIHIL language: the NixOS snowflake drawn with LED dots
# (theme/art/snowflake-19.txt) and monochrome, uppercase keys.

{ config, osConfig, pkgs, lib, ... }:
let
	# Empty rows are dropped: the logo's padding sets the spacing instead.
	grid = lib.filter (row: lib.any (cell: cell != "0") (lib.stringToCharacters row))
		(lib.splitString "\n" (lib.removeSuffix "\n" (builtins.readFile ../theme/art/snowflake-19.txt)));

	# Coverage 0-9 per cell: solid LED ($1), dim LED ($2) or nothing.
	led = cell:
		let v = lib.toInt cell; in
		if v >= 5 then "$1● " else if v >= 2 then "$2· " else "  ";

	logo = pkgs.writeText "nihil-fastfetch-logo" (lib.concatMapStringsSep "\n" (row: lib.concatMapStrings led (lib.stringToCharacters row)) grid);
in
{
	programs.fastfetch =
	{
		enable = true;
		settings =
		{
			logo =
			{
				type = "file";
				source = "${logo}";
				color = { "1" = "white"; "2" = "90"; };
				padding = { top = 1; left = 2; right = 4; };
			};

			display =
			{
				separator = "  ";
				color = { keys = "90"; title = "white"; separator = "90"; };
				key.width = 11;
			};

			modules =
			[
				{ type = "title"; format = "{user-name}@{host-name}"; }
				{ type = "custom"; format = "ex nihilo"; outputColor = "90"; }
				"break"
				{ type = "os"; key = "OS"; }
				{ type = "kernel"; key = "KERNEL"; }
				{ type = "uptime"; key = "UPTIME"; }
				{ type = "packages"; key = "PACKAGES"; }
				{ type = "wm"; key = "WM"; }
				{ type = "shell"; key = "SHELL"; }
				{ type = "terminal"; key = "TERMINAL"; }
				{ type = "cpu"; key = "CPU"; }
				{ type = "memory"; key = "MEMORY"; }
				{ type = "disk"; key = "DISK"; folders = "/"; }
				{ type = "battery"; key = "BATTERY"; }
				"break"
				{ type = "colors"; symbol = "circle"; }
			];
		};
	};
}
