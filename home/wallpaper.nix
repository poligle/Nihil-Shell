# wallpaper.nix by poligle

{ config, osConfig, pkgs, lib, ... }:
let
	nihil = osConfig.nihil;
	hyprctl = "${osConfig.programs.hyprland.package}/bin/hyprctl";

	nihil-wallpaper = pkgs.writeShellScriptBin "nihil-wallpaper" ''
		set -euo pipefail
		export PATH="${lib.makeBinPath [ pkgs.awww pkgs.jq pkgs.coreutils pkgs.procps ]}:${config.home.profileDirectory}/bin:$PATH"

		dir="${nihil.wallpapers}"
		state="${config.xdg.stateHome}/nihil/wallpaper"
		glass="${config.xdg.stateHome}/nihil/glass"
		names=( ${lib.escapeShellArgs nihil.wallpapers.names} )

		current() {
			if [ -r "$state" ] && [ -d "$dir/$(cat "$state")" ]; then
				cat "$state"
			else
				echo "${nihil.wallpaper}"
			fi
		}

		apply() {
			local name="$1" output file
			[ -d "$dir/$name" ] || { echo "nihil-wallpaper: unknown wallpaper '$name'" >&2; exit 1; }
			mkdir -p "$(dirname "$state")"
			echo "$name" > "$state"
			ln -sfn "$dir/$name" "$state-current"
			if [ -w /var/lib/nihil/greeter ]; then
				ln -sfn "$dir/$name/${nihil.primaryOutput}.png" /var/lib/nihil/greeter/wallpaper.png
				look > /var/lib/nihil/greeter/glass
			fi
			for output in $(${hyprctl} -j monitors | jq -r '.[].name'); do
				file="$dir/$name/$output.gif"
				[ -r "$file" ] || file="$dir/$name/$output.png"
				[ -r "$file" ] || file="$dir/$name/${nihil.primaryOutput}.png"
				awww img --outputs "$output" "$file"
			done
			if command -v nihil-lock-glass > /dev/null; then
				nihil-lock-glass > /dev/null 2>&1 &
			fi
		}

		look() {
			if [ "$(cat "$glass" 2> /dev/null)" = on ]; then echo on; else echo off; fi
		}

		step() {
			local now i count=''${#names[@]}
			now="$(current)"
			for i in "''${!names[@]}"; do
				if [ "''${names[$i]}" = "$now" ]; then
					apply "''${names[$(( (i + $1 + count) % count ))]}"
					return
				fi
			done
			apply "''${names[0]}"
		}

		case "''${1:-restore}" in
			restore) apply "$(current)" ;;
			next)    step 1 ;;
			prev)    step -1 ;;
			set)     apply "''${2:?usage: nihil-wallpaper set <name>}" ;;
			list)    printf '%s\n' "''${names[@]}" ;;
			current) current ;;
			glass)
				case "''${2:-}" in
					"") look ;;
					on | off)
						mkdir -p "$(dirname "$glass")"
						echo "$2" > "$glass"
						apply "$(current)"
						pkill -USR1 -x 'kitty|\.kitty-wrapped' || true
						;;
					*) echo "usage: nihil-wallpaper glass [on|off]" >&2; exit 2 ;;
				esac
				;;
			*)       echo "usage: nihil-wallpaper [restore|next|prev|set <name>|list|current|glass [on|off]]" >&2; exit 2 ;;
		esac
	'';
in
{
	home.packages = [ nihil-wallpaper ];

	systemd.user.services.awww-daemon =
	{
		Unit =
		{
			Description = "Wayland Wallpaper Daemon";
			After = [ "graphical-session.target" ];
			PartOf = [ "graphical-session.target" ];
		};

		Service =
		{
			ExecStart = "${pkgs.awww}/bin/awww-daemon";
			ExecStartPost = "${nihil-wallpaper}/bin/nihil-wallpaper restore";
			Restart = "on-failure";
		};

		Install =
		{
			WantedBy = [ "graphical-session.target" ];
		};
	};
}
