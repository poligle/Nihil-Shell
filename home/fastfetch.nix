# fastfetch.nix by poligle
#
# fastfetch in the NIHIL language: the NixOS snowflake drawn with LED dots
# (theme/art/snowflake-19.txt) and monochrome keys in sentence case. The colours
# are NIHIL's own, in 24 bits: the terminal's "bright black" is darker than
# any of them, and keys in it were hard to read on black.

{ config, osConfig, pkgs, lib, ... }:
let
	# Empty rows are dropped: the logo's padding sets the spacing instead.
	grid = lib.filter (row: lib.any (cell: cell != "0") (lib.stringToCharacters row))
		(lib.splitString "\n" (lib.removeSuffix "\n" (builtins.readFile ../theme/art/snowflake-19.txt)));

	led = cell:
		let v = lib.toInt cell; in
		if v >= 5 then "$1● " else if v >= 2 then "$2· " else "  ";

	logo = pkgs.writeText "nihil-fastfetch-logo" (lib.concatMapStringsSep "\n" (row: lib.concatMapStrings led (lib.stringToCharacters row)) grid);

	# A palette colour as fastfetch takes it: the parameters of an ANSI
	# 24-bit colour, "38;2;R;G;B".
	p = osConfig.nihil.tokens.palette;
	digit = c: lib.toInt c;
	hex = { a = 10; b = 11; c = 12; d = 13; e = 14; f = 15; };
	nibble = c: let l = lib.toLower c; in hex.${l} or (digit l);
	byte = s: toString (16 * nibble (builtins.substring 0 1 s) + nibble (builtins.substring 1 1 s));
	ansi = colour: "38;2;${byte (builtins.substring 0 2 colour)};${byte (builtins.substring 2 2 colour)};${byte (builtins.substring 4 2 colour)}";

	# The palette as a row of LEDs, from the dimmest lit one to the red that
	# only interrupts (the terminal's eight colours were half black here).
	esc = builtins.fromJSON ''"\u001b"'';
	leds = lib.concatMapStrings (colour: "${esc}[${ansi colour}m● ") [ p.muted p.dim p.ink p.ink p.ink p.dim p.muted p.signal ] + "${esc}[0m";
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
				color = { "1" = ansi p.ink; "2" = ansi p.muted; };
				padding = { top = 1; left = 2; right = 4; };
			};

			display =
			{
				separator = "  ";
				color = { keys = ansi p.dim; title = ansi p.ink; separator = ansi p.muted; };
				key.width = 11;
			};

			modules =
			[
				{ type = "title"; format = "{user-name}@{host-name}"; }
				{ type = "custom"; format = "Ex nihilo"; outputColor = ansi p.muted; }
				"break"
				{ type = "os"; key = "OS"; }
				{ type = "kernel"; key = "Kernel"; }
				{ type = "uptime"; key = "Uptime"; }
				{ type = "packages"; key = "Packages"; }
				{ type = "wm"; key = "WM"; }
				{ type = "shell"; key = "Shell"; }
				{ type = "terminal"; key = "Terminal"; }
				{ type = "cpu"; key = "CPU"; }
				{ type = "memory"; key = "Memory"; }
				{ type = "disk"; key = "Disk"; folders = "/"; }
				{ type = "battery"; key = "Battery"; }
				"break"
				{ type = "custom"; format = leds; }
			];
		};
	};
}
