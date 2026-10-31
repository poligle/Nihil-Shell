# hyprlock.nix by poligle

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

	python = pkgs.python3.withPackages (ps: [ ps.numpy ps.pillow ]);

	# cover renderer
	cover = pkgs.runCommand "nihil-lock-cover"
	{
		nativeBuildInputs = [ python pkgs.makeWrapper ];
	} ''
		mkdir -p $out/bin $out/share
		cp ${../theme/dotmatrix.py} $out/share/dotmatrix.py
		cp ${./lock/cover.py} $out/share/cover.py
		python3 $out/share/cover.py --placeholder $out/share/noart.png
		python3 $out/share/cover.py --blank $out/share/blank.png
		rm -rf $out/share/__pycache__
		makeWrapper ${python}/bin/python3 $out/bin/nihil-lock-cover \
			--set PYTHONDONTWRITEBYTECODE 1 --add-flags $out/share/cover.py
	'';

	media = pkgs.writeShellScript "nihil-lock-media" (''
		export PATH=${lib.makeBinPath [ pkgs.playerctl pkgs.coreutils pkgs.util-linux pkgs.curl ]}
		export INK=${t.palette.ink} DIM=${t.palette.dim} MUTED=${t.palette.muted}
		export SANS=${lib.escapeShellArg t.fonts.sans} MONO=${lib.escapeShellArg t.fonts.mono} ICONS=${lib.escapeShellArg t.fonts.icons}
		export PAUSED=${lib.escapeShellArg s.lockPaused}
		export RENDER=${cover}/bin/nihil-lock-cover BLANK=${cover}/share/blank.png NOART=${cover}/share/noart.png
	'' + builtins.readFile ./lock/media.sh);

	mediaLabel = attrs:
	{
		monitor = "";
		font_family = t.fonts.mono;
		font_size = 9;
		color = rgb t.palette.ink;
		halign = "left";
		valign = "bottom";
	} // attrs;

	shadow =
	{
		shadow_passes = 2;
		shadow_size = 5;
		shadow_color = rgb t.palette.void;
		shadow_boost = 1.4;
	};

	mediaButton = { action, x, y, every }: mediaLabel
	{
		text = "cmd[update:${toString every}] ${media} button ${action}";
		onclick = "${media} ${action}";
		position = "${toString x}, ${toString y}";
	};
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
				hide_cursor = false;
				ignore_empty_input = true;
			};

			background = backgrounds;

			image =
			[
				{
					monitor = "";
					path = "${cover}/share/blank.png";
					reload_cmd = "${media} cover";
					reload_time = 3;
					size = 120;
					rounding = 16;
					border_size = 0;
					position = "56, 88";
					halign = "left";
					valign = "bottom";
				}
			];

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

				(mediaLabel (shadow //
				{
					text = "cmd[update:2000] ${media} info";
					position = "198, 146";
				}))
				(mediaLabel (shadow //
				{
					text = "cmd[update:1000] ${media} progress";
					position = "56, 56";
				}))
				(mediaButton { action = "prev"; x = 186; y = 94; every = 3000; })
				(mediaButton { action = "toggle"; x = 222; y = 88; every = 1000; })
				(mediaButton { action = "next"; x = 272; y = 94; every = 3000; })
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
