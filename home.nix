{ config, pkgs, lib, ... }:
{
	home.username = "poligle";
	home.homeDirectory = "/home/poligle";
	home.stateVersion = "26.05";
	programs.home-manager.enable = true;
	programs.kitty = {
		enable = true;
		settings = {
			font_size = 12;
			background_opacity = "0.9";
		};
	};

	home.packages = with pkgs; [
		wofi
		waybar
	];
	wayland.windowManager.hyprland = {
		enable = true;
		package = null;
		portalPackage = null;
		configType = "lua";
		settings =
			let
				lua = lib.generators.mkLuaInline;
				bind = key: action: { _args = [ key (lua action) ]; };
				exec = cmd: ''hl.dsp.exec_cmd("${cmd}")'';
				ws = n: ''hl.dsp.focus({ workspace = "${n}" })'';
				mvws = n: ''hl.dsp.window.move({ workspace = "${n}" })'';
			in
			{
				bind = [
					(bind "SUPER + Q" (exec "kitty"))
					(bind "SUPER + SPACE" (exec "wofi"))
					(bind "SUPER + X" (exec "firefox"))
					(bind "SUPER + C" ''hl.dsp.window.close()'')
					(bind "SUPER + V" ''hl.dsp.window.float({})'')
					(bind "SUPER + F" ''hl.dsp.window.fullscreen({ mode = "maximized" })'')
					(bind "SUPER + 1" (ws "1"))
					(bind "SUPER + 2" (ws "2"))
					(bind "SUPER + 3" (ws "3"))
				];
			};
		extraConfig = ''
			hl.monitor({
			  output = "",
			  mode = "preferred",
			  position = "auto",
			  scale = 1
			})

			hl.config({
			  input = {
			    kb_layout = "es",
			    kb_variant = "",
			    follow_mouse = 1,
			    touchpad = {
			      natural_scroll = false
			    }
			  }
			})
		'';
	};
}
