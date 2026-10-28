# refresh.nix by poligle
#
# After every switch, reload Hyprland inside the running session: it doesn't
# notice that hyprland.lua now points to a new store path. The NIHIL shell is
# a systemd user service, so Home Manager restarts it on its own.

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
in
{
	xdg.configFile."hypr/hyprland.lua".onChange = forEachHyprland "reload config-only";
}
