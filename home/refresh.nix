# refresh.nix by poligle

{ config, osConfig, pkgs, lib, ... }:
let
	hyprctl = "${osConfig.programs.hyprland.package}/bin/hyprctl";

	forEachHyprland = command: ''
		(
			export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
			if [ -d "$XDG_RUNTIME_DIR/hypr" ]; then
				for instance in $(${hyprctl} instances -j | ${pkgs.jq}/bin/jq -r ".[].instance"); do
					${hyprctl} -i "$instance" ${command} >/dev/null || true
				done
			fi
		)
	'';

	runInSession = script: forEachHyprland "dispatch 'hl.dsp.exec_cmd(\"${script}\")'";

	waybar-restart = pkgs.writeShellScriptBin "waybar-restart" ''
		export PATH="${lib.makeBinPath [ pkgs.procps pkgs.util-linux pkgs.coreutils ]}:$PATH"
		exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/waybar-restart.lock"
		flock 9
		pkill -f waybar-autohide.py
		pkill -x .waybar-wrapped
		for attempt in $(seq 50); do
			pgrep -x .waybar-wrapped >/dev/null || break
			sleep 0.1
		done
		setsid -f ${config.programs.waybar.package}/bin/waybar >/dev/null 2>&1
		setsid -f waybar-autohide >/dev/null 2>&1
	'';

	eww-restart = pkgs.writeShellScriptBin "eww-restart" ''
		exec 9>"''${XDG_RUNTIME_DIR:-/tmp}/eww-restart.lock"
		${pkgs.util-linux}/bin/flock 9
		eww kill
		eww open-many window-clock window-network window-media
	'';

	restartWaybar = runInSession "${waybar-restart}/bin/waybar-restart";
	restartEww = runInSession "${eww-restart}/bin/eww-restart";
in
{
	home.packages =
	[
		waybar-restart
		eww-restart
	];

	xdg.configFile =
	{
		"hypr/hyprland.lua".onChange = forEachHyprland "reload config-only";
		"waybar/config".onChange = lib.mkForce restartWaybar;
		"waybar/style.css".onChange = lib.mkForce restartWaybar;
		"eww/eww.yuck".onChange = restartEww;
		"eww/eww.scss".onChange = restartEww;
	};
}
