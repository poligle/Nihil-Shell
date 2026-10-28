# nihil.nix by poligle
#
# NIHIL design tokens — ex nihilo.
# Plain data with no dependencies: the NixOS modules (Stylix), Home Manager
# (Hyprland, hyprlock, Neovim, VS Code) and the Quickshell shell all read
# from here, so the whole system follows a single source of truth.

let
	# Monochrome hierarchy. Red is never decoration: it only interrupts.
	# Contrast ratios against #000000 (WCAG 2.x relative luminance).
	palette =
	{
		void    = "000000";   # frame, bar, drawers (OLED black)
		surface = "0E0E0E";   # cards inside drawers           1.09:1
		raised  = "1A1A1A";   # hover, slider tracks            1.21:1
		line    = "2A2A2A";   # 1 px lines                      1.46:1
		off     = "333333";   # LEDs that are switched off      1.66:1
		muted   = "7A7A7A";   # metadata, inactive icons        4.89:1
		dim     = "A3A3A3";   # secondary text                  8.33:1
		ink     = "F2F2F2";   # primary text, lit LEDs         18.76:1
		signal  = "D71921";   # interrupts only (never small text, 4.05:1)
	};
in
{
	name = "NIHIL";
	motto = "ex nihilo";

	inherit palette;

	# Base16 view of the palette for Stylix. Accents become grey levels so
	# syntax highlighting is driven by luminance; base08 keeps the red for
	# errors, deletions and destructive actions.
	base16 =
	{
		scheme = "NIHIL";
		author = "poligle";

		base00 = palette.void;
		base01 = palette.surface;
		base02 = palette.raised;
		base03 = "5E5E5E";
		base04 = palette.muted;
		base05 = "E6E6E6";
		base06 = palette.ink;
		base07 = "FFFFFF";
		base08 = palette.signal;
		base09 = "CFCFCF";
		base0A = "FFFFFF";
		base0B = "9E9E9E";
		base0C = "8A8A8A";
		base0D = palette.ink;
		base0E = "B5B5B5";
		base0F = "6E6E6E";
	};

	# Three voices, like Nothing, with free fonts (Ndot is proprietary).
	# Doto is only used from ~20 px upwards.
	fonts =
	{
		dot   = "Doto";                     # dot matrix: clocks, big numbers
		sans  = "Space Grotesk";            # interface text
		mono  = "Space Mono";               # uppercase labels and metadata
		code  = "JetBrainsMono Nerd Font";  # terminal and editors
		icons = "JetBrainsMono Nerd Font";  # Material Design glyphs (nf-md)
	};

	# Frame geometry (px). The left side widens into the bar on the outputs
	# that have one.
	frame =
	{
		thickness    = 8;
		bar          = 44;
		radius       = 20;   # inner corners of the frame
		fillet       = 14;   # concave joint between frame and drawers
		drawerRadius = 22;   # convex corners of the drawers
	};

	# Windows sit concentric with the frame: rounding = radius - gapsOut.
	windows =
	{
		rounding = 12;
		gapsIn   = 4;
		gapsOut  = 8;
		border   = 1;
	};

	# Motion (ms): decisive deceleration, no bounce.
	motion =
	{
		fast   = 140;
		normal = 240;
		drawer = 320;
		slow   = 480;
	};
}
