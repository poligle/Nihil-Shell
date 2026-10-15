# scripts.nix by poligle

{ config, pkgs, lib, ... }:
let
	palette = config.lib.stylix.colors.withHashtag;
	volumeSound = "${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/audio-volume-change.oga";

	waybar-autohide = pkgs.writeShellScriptBin "waybar-autohide" ''
		export PATH="${lib.makeBinPath [ pkgs.procps pkgs.hyprland pkgs.jq ]}:$PATH"
		export WAYBAR_AUTOHIDE_PROCNAME=".waybar-wrapped"
		exec ${pkgs.python3}/bin/python3 ${./waybar-autohide.py} "$@"
	'';

    wofi-open = pkgs.writeShellScriptBin "wofi-open" ''
		exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/wofi.lock"
		if ! ${pkgs.util-linux}/bin/flock -n 9; then
			exit 0
		fi
		${pkgs.pipewire}/bin/pw-play --volume 0.4 ${../sounds/menu.ogg} &
		exec ${pkgs.wofi}/bin/wofi --show drun
	'';

	mic-led-sync = pkgs.writeShellScriptBin "mic-led-sync" ''
		set -euo pipefail
		LED="/sys/class/leds/platform::micmute/brightness"
		out="$(${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>&1 || true)"
		echo 0 > "$LED"
		if [[ "$out" == *"Could not connect to PipeWire"* ]]; then
			echo "mic-led-sync: PipeWire not reachable in this session." >&2
			exit 1
		fi
		if [[ "$out" == *"No such"* ]] || [[ "$out" == *"Unknown"* ]]; then
			echo "mic-led-sync: no valid DEFAULT_AUDIO_SOURCE. Output: $out" >&2
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
				${pkgs.pipewire}/bin/pw-play --volume 0.4 ${volumeSound} &
				;;
			down)
				${pkgs.wireplumber}/bin/wpctl set-mute "$sink" 0
				${pkgs.wireplumber}/bin/wpctl set-volume "$sink" "$step-"
				${pkgs.pipewire}/bin/pw-play --volume 0.4 ${volumeSound} &
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
				"  Volumen" "Mute"
		else
			${pkgs.dunst}/bin/dunstify -a osd -u low -t 900 \
				-h string:x-dunst-stack-tag:volume \
				-h int:value:"$vol" \
				"  Volumen" "''${vol}%"
		fi
	'';

	lock-screen = pkgs.writeShellScriptBin "lock-screen" ''
		${pkgs.pipewire}/bin/pw-play --volume 0.4 ${../sounds/lock.ogg} &
		exec ${pkgs.hyprlock}/bin/hyprlock
	'';

	power-off = pkgs.writeShellScriptBin "power-off" ''
		${pkgs.pipewire}/bin/pw-play --volume 0.5 ${../sounds/power.ogg}
		exec ${pkgs.systemd}/bin/systemctl poweroff
	'';

	bluetooth-status = pkgs.writeShellScriptBin "bluetooth-status" ''
		export PATH="${lib.makeBinPath [ pkgs.bluez pkgs.gnugrep pkgs.coreutils ]}:$PATH"
		if ! bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
			echo "󰂲 off"
			exit 0
		fi
		device="$(bluetoothctl devices Connected | cut -d" " -f3- | head -n1)"
		if [ -n "$device" ]; then
			echo "󰂱 $device"
		else
			echo " on"
		fi
	'';

	bluetooth-toggle = pkgs.writeShellScriptBin "bluetooth-toggle" ''
		export PATH="${lib.makeBinPath [ pkgs.bluez pkgs.gnugrep pkgs.util-linux pkgs.coreutils ]}:$PATH"
		if bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; then
			exec bluetoothctl power off
		fi
		rfkill unblock bluetooth
		for attempt in 1 2 3 4 5; do
			bluetoothctl power on >/dev/null 2>&1 && exit 0
			sleep 0.4
		done
		exit 1
	'';

	wofiMenuConf = pkgs.writeText "wofi-menu.conf" ''
		location=top_right
		xoffset=-10
		yoffset=55
		width=380
		height=360
		layer=overlay
		normal_window=false
		columns=1
		allow_images=false
		allow_markup=false
		insensitive=true
		hide_scroll=true
		no_actions=true
		dynamic_lines=false
		key_exit=Escape
	'';

	wofiMenuStyle = pkgs.writeText "wofi-menu.css" ''
		window
		{
			background-color: ${palette.base00};
			border-radius: 12px;
			font-family: "${config.stylix.fonts.monospace.name}";
			font-size: 14px;
		}
		#outer-box
		{
			padding: 8px;
		}
		#input
		{
			margin-bottom: 8px;
			padding: 6px 10px;
			border: none;
			border-radius: 8px;
			background-color: ${palette.base01};
			color: ${palette.base05};
		}
		#entry
		{
			padding: 6px 10px;
			border-radius: 8px;
		}
		#entry:selected
		{
			background-color: ${palette.base02};
		}
		#text
		{
			color: ${palette.base05};
		}
		#text:selected
		{
			color: ${palette.base0D};
		}
	'';

	wifi-status = pkgs.writeShellScriptBin "wifi-status" ''
		export PATH="${lib.makeBinPath [ pkgs.networkmanager pkgs.gnugrep pkgs.coreutils ]}:$PATH"
		if [ "$(nmcli -t -f WIFI general)" != "enabled" ]; then
			echo "󰖪 off"
			exit 0
		fi
		devices="$(nmcli -t -f TYPE,STATE,CONNECTION device status)"
		connection="$(printf '%s\n' "$devices" | grep "^wifi:connected:" | cut -d: -f3- | head -n1)"
		if [ -z "$connection" ]; then
			wired="$(printf '%s\n' "$devices" | grep "^ethernet:connected:" | cut -d: -f3- | head -n1)"
			if [ -n "$wired" ]; then
				echo "󰈀 $wired"
			else
				echo "󰤯 on"
			fi
			exit 0
		fi
		signal="$(nmcli -t -f IN-USE,SIGNAL device wifi list --rescan no | grep "^\*" | cut -d: -f2 | head -n1)"
		signal="''${signal:-0}"
		if [ "$signal" -ge 80 ]; then
			icon="󰤨"
		elif [ "$signal" -ge 60 ]; then
			icon="󰤥"
		elif [ "$signal" -ge 40 ]; then
			icon="󰤢"
		elif [ "$signal" -ge 20 ]; then
			icon="󰤟"
		else
			icon="󰤯"
		fi
		echo "$icon $connection"
	'';

	wifi-toggle = pkgs.writeShellScriptBin "wifi-toggle" ''
		if [ "$(${pkgs.networkmanager}/bin/nmcli -t -f WIFI general)" = "enabled" ]; then
			exec ${pkgs.networkmanager}/bin/nmcli radio wifi off
		fi
		exec ${pkgs.networkmanager}/bin/nmcli radio wifi on
	'';

	wifi-menu = pkgs.writeShellScriptBin "wifi-menu" ''
		export PATH="${lib.makeBinPath [ pkgs.networkmanager pkgs.wofi pkgs.libnotify pkgs.util-linux pkgs.coreutils pkgs.gnugrep ]}:$PATH"
		export WIFI_MENU_CONF="${wofiMenuConf}"
		export WIFI_MENU_STYLE="${wofiMenuStyle}"
		exec ${pkgs.bash}/bin/bash ${./wifi-menu.sh} "$@"
	'';
in
{
	home.packages = 
	[
		waybar-autohide
        wofi-open
		mic-led-sync
		osd-brightness
		osd-volume
		lock-screen
		power-off
		bluetooth-status
		bluetooth-toggle
		wifi-status
		wifi-toggle
		wifi-menu
	];

	home.file."Wallpapers".source = ../wallpapers;
}
