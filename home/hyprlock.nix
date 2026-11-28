# hyprlock.nix by poligle

{ config, osConfig, pkgs, lib, ... }:
let
	nihil = osConfig.nihil;
	t = nihil.tokens;
	s = nihil.strings;
	rgb = hex: "rgb(${hex})";

	state = "${config.xdg.stateHome}/nihil";
	# What the state's links point at: Home Manager's files, always this generation's, which no
	# collection takes while it lives. A link straight into the store kept an older generation's,
	# until a collection left it pointing at nothing.
	data = "${config.xdg.dataHome}/nihil";

	# A screen not in nihil.outputs, a projector say, gets the primary's without the field or the
	# panel, as it has neither, under each screen's own: a layer below theirs, as hyprlock's sort
	# doesn't keep the order of equal ones.
	backgrounds =
	[
		{
			monitor = "";
			path = "${state}/lock-current/fallback.png";
			color = rgb t.palette.void;
			zindex = -2;
		}
	] ++ lib.mapAttrsToList (output: _:
	{
		monitor = output;
		path = "${state}/lock-current/${output}.png";
		reload_cmd = "${media} backdrop ${output}";
		reload_time = 2;
		crossfade_time = 0.4;
		color = rgb t.palette.void;
	}) nihil.outputs;

	# The login screen's (greeter/shell.qml), made into the pictures: hyprlock's brightness is
	# its blur's, and darkens nothing without it. The wallpaper at 0.55, and under the column of
	# text 560 px wide, ramps of a fifth at its sides, darker still.
	dim = 0.55;
	column = { width = 560; ramp = 0.2; darkness = 0.7; };

	# hyprlock draws in a screen's pixels and scales nothing. While every one of nihil.outputs is
	# at 1, the same widgets go on any screen; else each of them gets its own, at its scale, and a
	# screen not there none, as hyprlock has no "every other screen".
	screens = if lib.all (o: o.scale == 1) (lib.attrValues nihil.outputs)
		then [ { monitor = ""; scale = 1; } ]
		else lib.mapAttrsToList (monitor: o: { inherit monitor; inherit (o) scale; }) nihil.outputs;
	scaled = scale: value: builtins.floor (value * scale + 0.5);
	at = scale: x: y: "${toString (scaled scale x)}, ${toString (scaled scale y)}";
	# Points for pixels, at 96 dpi: as a label's size, and in 1024ths, as Pango's markup takes it.
	points = scale: px: scaled scale (px * 0.75);
	markup = scale: px: toString (scaled scale (px * 0.75 * 1024));
	# A colour in Pango's markup: # would start a comment in hyprlock's configuration, ## is one.
	inMarkup = colour: "##${colour}";

	# As the login screen's: a pill under the clock, its words 13 px in grey, dots of 10 every 17
	# (hyprlock floors 10 x 0.71), and what went wrong in ink after the red LED.
	field = { width = 280; height = 46; y = -56; };

	panel = { x = 32; y = 32; width = 540; height = 200; radius = 40; };

	fieldStyle = scale:
	{
		dots_size = 0.22;
		dots_spacing = 0.71;
		dots_center = true;
		dots_rounding = -1;
		fade_on_empty = false;
		font_family = t.fonts.mono;
		font_color = rgb t.palette.ink;
		check_color = rgb t.palette.muted;
		fail_color = rgb t.palette.signal;
		placeholder_text = "<span font_family='${t.fonts.mono}' font_size='${markup scale 13}' foreground='${inMarkup t.palette.muted}'>${s.password}</span>";
		fail_text = "<span font_family='${t.fonts.sans}' font_weight='bold' font_size='${markup scale 14.5}' foreground='${inMarkup t.palette.signal}'>•</span>"
			+ "<span font_family='${t.fonts.mono}' font_size='${markup scale 13}' foreground='${inMarkup t.palette.ink}'> ${s.authFailed}</span>";
		halign = "center";
		valign = "center";
	};

	plainLook = pkgs.writeText "hyprlock-plain.conf" (lib.hm.generators.toHyprconf
	{
		attrs."input-field" = map (screen: fieldStyle screen.scale //
		{
			inherit (screen) monitor;
			size = at screen.scale field.width field.height;
			outline_thickness = scaled screen.scale 1;
			rounding = -1;
			outer_color = rgb t.palette.line;
			inner_color = rgb t.palette.void;
			position = at screen.scale 0 field.y;
		}) screens;
	});

	percent = part: whole: "${toString (part * 100.0 / whole)}%";
	# The pill is in the picture, at the screen's scale; the field over it, clear, in its place.
	glassLook = pkgs.writeText "hyprlock-glass.conf" (lib.hm.generators.toHyprconf
	{
		attrs."input-field" = lib.mapAttrsToList (output: o: fieldStyle o.scale //
		{
			monitor = output;
			size = "${percent field.width (o.width / o.scale)}, ${percent field.height (o.height / o.scale)}";
			outline_thickness = 1;
			rounding = -1;
			outer_color = "rgba(0, 0, 0, 0.0)";
			inner_color = "rgba(0, 0, 0, 0.0)";
			position = "0%, ${percent field.y (o.height / o.scale)}";
		}) nihil.outputs;
	});

	glassPython = pkgs.python3.withPackages (ps: [ ps.numpy ps.pillow ]);

	lockGlass = pkgs.writeShellApplication
	{
		name = "nihil-lock-glass";
		runtimeInputs = [ pkgs.coreutils pkgs.findutils pkgs.util-linux ];
		text = let
			glass = "${glassPython}/bin/python3 ${./lock/glass.py}";
			sizes = output: let o = nihil.outputs.${output}; in "--logical ${toString (o.width / o.scale)} ${toString (o.height / o.scale)}";
			darker = "--dim ${toString dim} --column ${toString column.width} ${toString column.ramp} ${toString column.darkness}";
			fieldArgs = "--field ${toString field.width} ${toString field.height} ${toString field.y}";
			panelArgs = "--panel ${toString panel.x} ${toString panel.y} ${toString panel.width} ${toString panel.height} ${toString panel.radius}";
			# What the pictures are made from and with: another, and they're made again.
			recipe = builtins.hashString "sha256" (builtins.toJSON
			{
				inherit dim column field panel;
				inherit (nihil) outputs primaryOutput;
				script = builtins.hashFile "sha256" ./lock/glass.py;
			});
		in ''
			state="${state}"
			data="${data}"
			install -d -m 700 "$state"
			plain() {
				ln -sfn "$state/wallpaper-current" "$state/lock-current"
				ln -sfn "$data/hyprlock-plain.conf" "$state/hyprlock-look.conf"
			}
			bake() {
				${lib.concatMapStringsSep "\n" (output: ''
					if [ "$1" = glass ]; then
						${glass} "$2/${output}.png" "$3/${output}.png" ${sizes output} ${darker} ${fieldArgs} || return 1
						${glass} "$2/${output}.png" "$3/${output}-media.png" ${sizes output} ${darker} ${fieldArgs} ${panelArgs} || return 1
					else
						${glass} "$2/${output}.png" "$3/${output}.png" ${sizes output} ${darker} || return 1
						${glass} "$2/${output}.png" "$3/${output}-media.png" ${sizes output} ${darker} ${panelArgs} --flat ${t.palette.void} ${t.palette.line} || return 1
					fi'') (lib.attrNames nihil.outputs)}
				${glass} "$2/${nihil.primaryOutput}.png" "$3/fallback.png" ${sizes nihil.primaryOutput} ${darker} || return 1
			}
			if [ "''${1:-}" = --links ]; then
				# Links from before, into the store, point at Home Manager's files now.
				wallpaper=$(readlink "$state/wallpaper-current" 2> /dev/null || true)
				case "$wallpaper" in
					/nix/store/*) ln -sfn "$data/wallpapers/''${wallpaper##*/}" "$state/wallpaper-current" ;;
				esac
				case "$(readlink "$state/hyprlock-look.conf" 2> /dev/null || true)" in
					"$data"/*) ;;
					*-hyprlock-glass.conf) ln -sfn "$data/hyprlock-glass.conf" "$state/hyprlock-look.conf" ;;
					*) plain ;;
				esac
				[ -L "$state/lock-current" ] || plain
				exit 0
			fi
			exec 9> "$state/.lock-glass"
			flock 9
			wall=$(readlink -f "$state/wallpaper-current" || true)
			if [ -z "$wall" ] || [ ! -d "$wall" ]; then
				plain
				exit 0
			fi
			look=plain
			if [ "$(cat "$state/glass" 2> /dev/null || true)" = on ]; then
				look=glass
			fi
			key=$(printf '%s %s %s' "$look" "$wall" "${recipe}" | sha1sum | cut -c1-16)
			made="$state/lock-$look/$key"
			if [ ! -e "$made/.done" ]; then
				rm -rf "$made.tmp"
				mkdir -p "$made.tmp"
				if ! bake "$look" "$wall" "$made.tmp"; then
					rm -rf "$made.tmp"
					plain
					exit 0
				fi
				touch "$made.tmp/.done"
				rm -rf "$made"
				mv "$made.tmp" "$made"
			fi
			ln -sfn "$made" "$state/lock-current"
			ln -sfn "$data/hyprlock-$look.conf" "$state/hyprlock-look.conf"
			for other in "$state/lock-glass" "$state/lock-plain"; do
				[ -d "$other" ] && find "$other" -mindepth 1 -maxdepth 1 ! -name "$key" -exec rm -rf {} +
			done
			exit 0
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
		export PAUSED=${lib.escapeShellArg s.lockPaused} LOCK=${lib.escapeShellArg "${state}/lock-current"}
		export RENDER=${cover}/bin/nihil-lock-cover BLANK=${cover}/share/blank.png NOART=${cover}/share/noart.png
	'' + builtins.readFile ./lock/media.sh);

	mediaLabel = screen: attrs:
	{
		inherit (screen) monitor;
		font_family = t.fonts.mono;
		font_size = points screen.scale 12;
		color = rgb t.palette.ink;
		halign = "left";
		valign = "bottom";
	} // attrs;

	shadow = screen:
	{
		shadow_passes = 2;
		shadow_size = scaled screen.scale 5;
		shadow_color = rgb t.palette.void;
		shadow_boost = 1.4;
	};

	mediaButton = screen: { action, x, y, every }: mediaLabel screen
	{
		text = "cmd[update:${toString every}] ${media} button ${action}";
		onclick = "${media} ${action}";
		position = at screen.scale x y;
	};

	# As the login screen's: the clock 160 px tall, 170 above the middle, and the date 72 above it.
	labels = screen:
	[
		{
			inherit (screen) monitor;
			text = "$TIME";
			font_family = "${t.fonts.dot} Bold";
			font_size = points screen.scale 160;
			color = rgb t.palette.ink;
			position = at screen.scale 0 170;
			halign = "center";
			valign = "center";
		}
		{
			inherit (screen) monitor;
			text = ''cmd[update:60000] LC_TIME=${s.lockLocale} ${pkgs.coreutils}/bin/date +'${s.lockDate}' | ${pkgs.gawk}/bin/awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }' '';
			font_family = t.fonts.mono;
			font_size = points screen.scale 16;
			color = rgb t.palette.dim;
			position = at screen.scale 0 72;
			halign = "center";
			valign = "center";
		}
		{
			inherit (screen) monitor;
			text = "$FPRINTPROMPT";
			font_family = t.fonts.mono;
			font_size = points screen.scale 12;
			color = rgb t.palette.muted;
			position = at screen.scale 0 (-110);
			halign = "center";
			valign = "center";
		}
		{
			inherit (screen) monitor;
			text = "<i>${t.motto}</i>";
			font_family = t.fonts.mono;
			font_size = points screen.scale 12;
			color = rgb t.palette.off;
			position = at screen.scale 0 40;
			halign = "center";
			valign = "bottom";
		}

		(mediaLabel screen (shadow screen //
		{
			text = "cmd[update:2000] ${media} info";
			position = at screen.scale 198 146;
		}))
		(mediaLabel screen (shadow screen //
		{
			text = "cmd[update:1000] ${media} progress";
			position = at screen.scale 56 56;
		}))
		(mediaButton screen { action = "prev"; x = 186; y = 94; every = 3000; })
		(mediaButton screen { action = "toggle"; x = 222; y = 88; every = 1000; })
		(mediaButton screen { action = "next"; x = 272; y = 94; every = 3000; })
	];
in
{
	stylix.targets.hyprlock.enable = false;

	home.packages = [ lockGlass ];

	xdg.dataFile."nihil/hyprlock-plain.conf".source = plainLook;
	xdg.dataFile."nihil/hyprlock-glass.conf".source = glassLook;

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

			image = map (screen:
			{
				inherit (screen) monitor;
				path = "${cover}/share/blank.png";
				reload_cmd = "${media} cover";
				reload_time = 3;
				size = scaled screen.scale 120;
				rounding = scaled screen.scale 16;
				border_size = 0;
				position = at screen.scale 56 88;
				halign = "left";
				valign = "bottom";
			}) screens;

			label = lib.concatMap labels screens;

			auth =
			{
				"fingerprint:enabled" = nihil.fingerprint;
				"fingerprint:ready_message" = s.fingerprintReady;
				"fingerprint:present_message" = s.fingerprintPresent;
			};
		};
	};
}