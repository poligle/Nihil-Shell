# wallpaper.nix by poligle
#
# awww shows the NIHIL dot-matrix renders, one file per output at its native
# size. `nihil-wallpaper` switches between them at runtime and remembers the
# choice:  nihil-wallpaper [restore|next|prev|set <name>|list|current]

{ config, osConfig, pkgs, lib, ... }:
let
	nihil = osConfig.nihil;
	hyprctl = "${osConfig.programs.hyprland.package}/bin/hyprctl";

	nihil-wallpaper = pkgs.writeShellScriptBin "nihil-wallpaper" ''
		set -euo pipefail
		export PATH="${lib.makeBinPath [ pkgs.awww pkgs.jq pkgs.coreutils ]}:$PATH"

		dir="${nihil.wallpapers}"
		state="${config.xdg.stateHome}/nihil/wallpaper"
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
			for output in $(${hyprctl} -j monitors | jq -r '.[].name'); do
				file="$dir/$name/$output.png"
				[ -r "$file" ] || file="$dir/$name/${nihil.primaryOutput}.png"
				awww img --outputs "$output" "$file"
			done
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
			*)       echo "usage: nihil-wallpaper [restore|next|prev|set <name>|list|current]" >&2; exit 2 ;;
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
