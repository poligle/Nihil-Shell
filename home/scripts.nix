# scripts.nix by poligle

{ config, pkgs, lib, ... }:
let
	
	waybar-autohide = pkgs.writeShellScriptBin "waybar-autohide" ''
		export PATH="${lib.makeBinPath [ pkgs.procps pkgs.hyprland pkgs.jq ]}:$PATH"
		export WAYBAR_AUTOHIDE_PROCNAME=".waybar-wrapped"
		exec ${pkgs.python3}/bin/python3 ${./waybar-autohide.py} "$@"
	'';

	mic-led-sync = pkgs.writeShellScriptBin "mic-led-sync" ''
		set -euo pipefail
		LED="/sys/class/leds/platform::micmute/brightness"
		out="$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>&1 || true)"
		echo 0 > "$LED"
		if [[ "$out" == *"Could not connect to PipeWire"* ]]; then
		    echo "mic-led-sync: PipeWire no accesible en esta sesión." >&2
		    exit 1
		fi
		if [[ "$out" == *"No such"* ]] || [[ "$out" == *"Unknown"* ]]; then
		    echo "mic-led-sync: no hay DEFAULT_AUDIO_SOURCE válido. Salida: $out" >&2
		    exit 1
		fi
		if echo "$out" | ${pkgs.gnugrep}/bin/grep -q "MUTED"; then
		    echo 1 > "$LED"
		else
		    echo 0 > "$LED"
		fi
	'';

	osd-brightness = pkgs.writeShellScriptBin "osd-brightness" ''
		step="5%"
		case "$1" in
		    up)
		        ${pkgs.brightnessctl}/bin/brightnessctl set +"$step" >/dev/null
		        ;;
		    down)
		        ${pkgs.brightnessctl}/bin/brightnessctl set "$step"- >/dev/null
		        ;;
		esac
		br="$(${pkgs.brightnessctl}/bin/brightnessctl -m | ${pkgs.gawk}/bin/awk -F, '{gsub("%","",$4); print $4}')"
		${pkgs.dunst}/bin/dunstify -a osd -u low -t 900 \
		    -h string:x-dunst-stack-tag:brightness \
		    -h int:value:"$br" \
		    "󰃠  Brillo" "''${br}%"
	'';

	osd-volume = pkgs.writeShellScriptBin "osd-volume" ''
		sink="@DEFAULT_AUDIO_SINK@"
		step="5%"
		case "$1" in
		    up)
		        ${pkgs.wireplumber}/bin/wpctl set-mute "$sink" 0
		        ${pkgs.wireplumber}/bin/wpctl set-volume -l 1 "$sink" "$step+"
		        ;;
		    down)
		        ${pkgs.wireplumber}/bin/wpctl set-mute "$sink" 0
		        ${pkgs.wireplumber}/bin/wpctl set-volume "$sink" "$step-"
		        ;;
		    mute)
		        ${pkgs.wireplumber}/bin/wpctl set-mute "$sink" toggle
		        ;;
		esac
		state="$(${pkgs.wireplumber}/bin/wpctl get-volume "$sink")"
		vol="$(${pkgs.gawk}/bin/awk '{printf "%d", $2 * 100}' <<< "$state")"
		if ${pkgs.gnugrep}/bin/grep -q MUTED <<< "$state"; then
		    ${pkgs.dunst}/bin/dunstify -a osd -u low -t 900 \
		        -h string:x-dunst-stack-tag:volume \
		        -h int:value:0 \
		        "󰖁 Volumen" "Mute"
		else
		    ${pkgs.dunst}/bin/dunstify -a osd -u low -t 900 \
		        -h string:x-dunst-stack-tag:volume \
		        -h int:value:"$vol" \
		        "󰕾 Volumen" "''${vol}%"
		fi
	'';
in
{
	home.packages = [
		waybar-autohide
		mic-led-sync
		osd-brightness
		osd-volume
	];

    home.file.".wallpapers".source = ../wallpapers;
}
