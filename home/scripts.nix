# scripts.nix by poligle
#
# Scripts bound to keys. The OSD ones change the value and report it to the
# NIHIL shell, which draws it on the frame (nihil-ipc osd ...).

{ config, osConfig, pkgs, lib, ... }:
let
	ipc = "${config.home.profileDirectory}/bin/nihil-ipc";
	wpctl = "${pkgs.wireplumber}/bin/wpctl";
	grep = "${pkgs.gnugrep}/bin/grep";
	awk = "${pkgs.gawk}/bin/awk";
	brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
	sound = osConfig.nihil.sounds;
	volumeSound = sound.volume;

	mic-led-sync = pkgs.writeShellScriptBin "mic-led-sync" ''
		set -euo pipefail
		LED="/sys/class/leds/platform::micmute/brightness"
		out="$(${wpctl} get-volume @DEFAULT_AUDIO_SOURCE@ 2>&1 || true)"
		echo 0 > "$LED"
		if [[ "$out" == *"Could not connect to PipeWire"* ]]; then
			echo "mic-led-sync: PipeWire not reachable in this session." >&2
			exit 1
		fi
		if [[ "$out" == *"No such"* ]] || [[ "$out" == *"Unknown"* ]]; then
			echo "mic-led-sync: no valid DEFAULT_AUDIO_SOURCE. Output: $out" >&2
			exit 1
		fi
		if echo "$out" | ${grep} -q "MUTED"; then
			echo 1 > "$LED"
		else
			echo 0 > "$LED"
		fi
	'';

	osd-brightness = pkgs.writeShellScriptBin "osd-brightness" ''
		step="5%"
		case "$1" in
			up)
				${brightnessctl} set +"$step" >/dev/null
				;;
			down)
				${brightnessctl} set "$step"- >/dev/null
				;;
		esac
		br="$(${brightnessctl} -m | ${awk} -F, '{gsub("%","",$4); print $4}')"
		exec ${ipc} osd brightness "$br" >/dev/null 2>&1
	'';

	osd-volume = pkgs.writeShellScriptBin "osd-volume" ''
		sink="@DEFAULT_AUDIO_SINK@"
		step="5%"
		case "$1" in
			up)
				${wpctl} set-mute "$sink" 0
				${wpctl} set-volume -l 1 "$sink" "$step+"
				${pkgs.pipewire}/bin/pw-play --volume 0.4 ${volumeSound} &
				;;
			down)
				${wpctl} set-mute "$sink" 0
				${wpctl} set-volume "$sink" "$step-"
				${pkgs.pipewire}/bin/pw-play --volume 0.4 ${volumeSound} &
				;;
			mute)
				${wpctl} set-mute "$sink" toggle
				;;
		esac
		state="$(${wpctl} get-volume "$sink")"
		vol="$(${awk} '{printf "%d", $2 * 100}' <<< "$state")"
		muted=false
		if ${grep} -q MUTED <<< "$state"; then
			muted=true
		fi
		exec ${ipc} osd volume "$vol" "$muted" >/dev/null 2>&1
	'';

	osd-mic = pkgs.writeShellScriptBin "osd-mic" ''
		${wpctl} set-mute @DEFAULT_AUDIO_SOURCE@ toggle
		${mic-led-sync}/bin/mic-led-sync || true
		muted=false
		if ${wpctl} get-volume @DEFAULT_AUDIO_SOURCE@ | ${grep} -q MUTED; then
			muted=true
		fi
		exec ${ipc} osd mic "$muted" >/dev/null 2>&1
	'';

	lock-screen = pkgs.writeShellScriptBin "lock-screen" ''
		${pkgs.pipewire}/bin/pw-play --volume 0.4 ${sound.lock} &
		exec ${pkgs.hyprlock}/bin/hyprlock
	'';

	power-off = pkgs.writeShellScriptBin "power-off" ''
		${pkgs.pipewire}/bin/pw-play --volume 0.5 ${sound.power}
		exec ${pkgs.systemd}/bin/systemctl poweroff
	'';
in
{
	home.packages =
	[
		mic-led-sync
		osd-brightness
		osd-volume
		osd-mic
		lock-screen
		power-off
	];

	home.file."Wallpapers".source = ../wallpapers;
}
