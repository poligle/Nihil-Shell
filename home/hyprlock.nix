# hyprlock.nix by poligle

{ config, osConfig, pkgs, lib, ... }:
let
	nihil = osConfig.nihil;
	t = nihil.tokens;
	s = nihil.strings;
	rgb = hex: "rgb(${hex})";

	state = "${config.xdg.stateHome}/nihil";

	backgrounds = lib.mapAttrsToList (output: _:
	{
		monitor = output;
		path = "${state}/lock-current/${output}.png";
		color = rgb t.palette.void;
		brightness = 0.55;
	}) nihil.outputs;

	field = { width = 280; height = 46; y = -40; };

	fieldStyle =
	{
		dots_size = 0.22;
		dots_spacing = 0.65;
		dots_center = true;
		dots_rounding = -1;
		fade_on_empty = false;
		font_color = rgb t.palette.ink;
		check_color = rgb t.palette.muted;
		fail_color = rgb t.palette.signal;
		placeholder_text = "<span font_family='${t.fonts.mono}'>${s.password}</span>";
		fail_text = "<span font_family='${t.fonts.mono}'>${s.authFailed}</span>";
		halign = "center";
		valign = "center";
	};

	plainLook = pkgs.writeText "hyprlock-plain.conf" (lib.hm.generators.toHyprconf
	{
		attrs."input-field" = fieldStyle //
		{
			monitor = "";
			size = "${toString field.width}, ${toString field.height}";
			outline_thickness = 1;
			rounding = -1;
			outer_color = rgb t.palette.line;
			inner_color = rgb t.palette.void;
			position = "0, ${toString field.y}";
		};
	});

	percent = part: whole: "${toString (part * 100.0 / whole)}%";
	glassLook = pkgs.writeText "hyprlock-glass.conf" (lib.hm.generators.toHyprconf
	{
		attrs."input-field" = lib.mapAttrsToList (output: o: fieldStyle //
		{
			monitor = output;
			size = "${percent field.width o.width}, ${percent field.height o.height}";
			outline_thickness = 1;
			rounding = -1;
			outer_color = "rgba(0, 0, 0, 0.0)";
			inner_color = "rgba(0, 0, 0, 0.0)";
			position = "0%, ${percent field.y o.height}";
		}) nihil.outputs;
	});

	glassPython = pkgs.python3.withPackages (ps: [ ps.numpy ps.pillow ]);

	lockGlass = pkgs.writeShellApplication
	{
		name = "nihil-lock-glass";
		runtimeInputs = [ pkgs.coreutils pkgs.findutils ];
		text = ''
			state="${state}"
			mkdir -p "$state"
			plain() {
				ln -sfn "$state/wallpaper-current" "$state/lock-current"
				ln -sfn ${plainLook} "$state/hyprlock-look.conf"
			}
			if [ "''${1:-}" = --links ]; then
				[ -e "$state/hyprlock-look.conf" ] || plain
				[ -L "$state/lock-current" ] || plain
				exit 0
			fi
			if [ "$(cat "$state/glass" 2> /dev/null || true)" != on ]; then
				plain
				exit 0
			fi
			wall=$(readlink -f "$state/wallpaper-current" || true)
			if [ -z "$wall" ] || [ ! -d "$wall" ]; then
				plain
				exit 0
			fi
			key=$(printf '%s' "$wall" | sha1sum | cut -c1-16)
			made="$state/lock-glass/$key"
			if [ ! -e "$made/.done" ]; then
				rm -rf "$made.tmp"
				mkdir -p "$made.tmp"
				${lib.concatMapStringsSep "\n" (output: let o = nihil.outputs.${output}; in ''
					if ! ${glassPython}/bin/python3 ${./lock/glass.py} "$wall/${output}.png" "$made.tmp/${output}.png" \
						--logical ${toString o.width} ${toString o.height} \
						--field ${toString field.width} ${toString field.height} ${toString field.y}; then
						rm -rf "$made.tmp"
						plain
						exit 0
					fi'') (lib.attrNames nihil.outputs)}
				touch "$made.tmp/.done"
				rm -rf "$made"
				mv "$made.tmp" "$made"
			fi
			ln -sfn "$made" "$state/lock-current"
			ln -sfn ${glassLook} "$state/hyprlock-look.conf"
			find "$state/lock-glass" -mindepth 1 -maxdepth 1 ! -name "$key" -exec rm -rf {} +
		'';
	};

	python = pkgs.python3.withPackages (ps: [ ps.numpy ps.pillow ]);

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

	home.packages = [ lockGlass ];

	home.activation.nihilLockLinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
		run ${lockGlass}/bin/nihil-lock-glass --links
	'';

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

			source = [ "${state}/hyprlock-look.conf" ];

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
					text = ''cmd[update:60000] LC_TIME=${s.lockLocale} ${pkgs.coreutils}/bin/date +'${s.lockDate}' | ${pkgs.gawk}/bin/awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }' '';
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
					text = "<i>${t.motto}</i>";
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

			auth =
			{
				"fingerprint:enabled" = nihil.fingerprint;
				"fingerprint:ready_message" = s.fingerprintReady;
				"fingerprint:present_message" = s.fingerprintPresent;
			};
		};
	};
}