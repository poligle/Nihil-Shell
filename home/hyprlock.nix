# hyprlock.nix by poligle
#
# NIHIL lock screen: dot-matrix wallpaper per output, Doto clock, and the
# password drawn as a row of dots that light up while typing. Fingerprint
# stays enabled; red only appears when authentication fails.

{ config, osConfig, pkgs, lib, ... }:
let
	nihil = osConfig.nihil;
	t = nihil.tokens;
	s = nihil.strings;
	rgb = hex: "rgb(${hex})";

	backgrounds = lib.mapAttrsToList (output: _:
	{
		monitor = output;
		path = "${nihil.wallpapers}/${nihil.wallpaper}/${output}.png";
		color = rgb t.palette.void;
		brightness = 0.55;
	}) nihil.outputs;
in
{
	stylix.targets.hyprlock.enable = false;

	programs.hyprlock =
	{
		enable = true;
		settings =
		{
			general =
			{
				hide_cursor = true;
				ignore_empty_input = true;
			};

			background = backgrounds;

			label =
			[
				{
					monitor = "";
					text = "$TIME";
					font_family = "${t.fonts.dot} Bold";
					font_size = 128;
					color = rgb t.palette.ink;
					position = "0, 150";
					halign = "center";
					valign = "center";
				}
				{
					monitor = "";
					text = ''cmd[update:60000] LC_TIME=${s.lockLocale} ${pkgs.coreutils}/bin/date +'${s.lockDate}' | ${pkgs.gawk}/bin/awk '{ print toupper($0) }' '';
					font_family = t.fonts.mono;
					font_size = 13;
					color = rgb t.palette.dim;
					position = "0, 50";
					halign = "center";
					valign = "center";
				}
				{
					monitor = "";
					text = "$FPRINTPROMPT";
					font_family = t.fonts.mono;
					font_size = 10;
					color = rgb t.palette.muted;
					position = "0, -110";
					halign = "center";
					valign = "center";
				}
				{
					monitor = "";
					text = t.motto;
					font_family = t.fonts.mono;
					font_size = 10;
					color = rgb t.palette.off;
					position = "0, 40";
					halign = "center";
					valign = "bottom";
				}
			];

			"input-field" =
			{
				monitor = "";
				size = "280, 46";
				outline_thickness = 1;
				rounding = -1;
				outer_color = rgb t.palette.line;
				inner_color = rgb t.palette.void;
				font_color = rgb t.palette.ink;
				check_color = rgb t.palette.muted;
				fail_color = rgb t.palette.signal;
				dots_size = 0.22;
				dots_spacing = 0.65;
				dots_center = true;
				dots_rounding = -1;
				fade_on_empty = false;
				placeholder_text = "<span font_family='${t.fonts.mono}'>${s.password}</span>";
				fail_text = "<span font_family='${t.fonts.mono}'>${s.authFailed}</span>";
				position = "0, -40";
				halign = "center";
				valign = "center";
			};

			auth =
			{
				"fingerprint:enabled" = true;
				"fingerprint:ready_message" = s.fingerprintReady;
				"fingerprint:present_message" = s.fingerprintPresent;
			};
		};
	};
}
