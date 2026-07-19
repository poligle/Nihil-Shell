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
				bindo = key: action: opts: { _args = [ key (lua action) (lua opts) ]; };
				exec = cmd: ''hl.dsp.exec_cmd("${cmd}")'';
				ws = n: ''hl.dsp.focus({ workspace = "${n}" })'';
				mvws = n: ''hl.dsp.window.move({ workspace = "${n}" })'';
			in
			{
				bind = [
					# Apps (available)
					(bind "SUPER + Super_L" (exec "kitty"))
					(bind "SUPER + Space" (exec "wofi"))
					(bind "SUPER + E" (exec "nautilus"))
					(bind "SUPER + X" (exec "firefox"))

					# Apps (not installed yet - commented)
					# (bind "SUPER + P" (exec "solanum"))
					# (bind "SUPER + N" (exec "obsidian"))
					# (bind "SUPER + C" (exec "code"))
					# (bind "SUPER + S" (exec "spotify"))
					# (bind "SUPER + H" (exec "hyprpicker -a"))
					# (bind "SUPER + K" (exec "hyprlock"))

					# Window management
					(bind "SUPER + Q" ''hl.dsp.window.close()'')
					(bind "SUPER + V" ''hl.dsp.window.float({ action = "toggle" })'')
					(bind "SUPER + F" ''hl.dsp.window.fullscreen({ mode = "maximized" })'')
					(bind "SUPER + SHIFT + F" ''hl.dsp.window.fullscreen({ mode = "fullscreen" })'')

					# Move focus
					(bind "SUPER + left" ''hl.dsp.focus({ direction = "left" })'')
					(bind "SUPER + right" ''hl.dsp.focus({ direction = "right" })'')
					(bind "SUPER + up" ''hl.dsp.focus({ direction = "up" })'')
					(bind "SUPER + down" ''hl.dsp.focus({ direction = "down" })'')

					# Special workspace
					(bind "SUPER + Escape" ''hl.dsp.workspace.toggle_special()'')

					# Workspaces
					(bind "SUPER + 1" (ws "1"))
					(bind "SUPER + 2" (ws "2"))
					(bind "SUPER + 3" (ws "3"))
					(bind "SUPER + 4" (ws "4"))
					(bind "SUPER + 5" (ws "5"))
					(bind "SUPER + 6" (ws "6"))
					(bind "SUPER + 7" (ws "7"))
					(bind "SUPER + 8" (ws "8"))
					(bind "SUPER + 9" (ws "9"))
					(bind "SUPER + 0" (ws "10"))

					# Move window to workspace
					(bind "SUPER + SHIFT + 1" (mvws "1"))
					(bind "SUPER + SHIFT + 2" (mvws "2"))
					(bind "SUPER + SHIFT + 3" (mvws "3"))
					(bind "SUPER + SHIFT + 4" (mvws "4"))
					(bind "SUPER + SHIFT + 5" (mvws "5"))
					(bind "SUPER + SHIFT + 6" (mvws "6"))
					(bind "SUPER + SHIFT + 7" (mvws "7"))
					(bind "SUPER + SHIFT + 8" (mvws "8"))
					(bind "SUPER + SHIFT + 9" (mvws "9"))
					(bind "SUPER + SHIFT + 0" (mvws "10"))

					# Multimedia keys (not installed yet - commented)
					# (bindo "PRINT" (exec "hyprshot -m output --clipboard-only") ''{ locked = true }'')
					# (bindo "F10" (exec "hyprshot -m region --clipboard-only") ''{ locked = true }'')
					# (bindo "XF86AudioNext" (exec "playerctl next") ''{ locked = true }'')
					# (bindo "XF86AudioPause" (exec "playerctl play-pause") ''{ locked = true }'')
					# (bindo "XF86AudioPlay" (exec "playerctl play-pause") ''{ locked = true }'')
					# (bindo "XF86AudioPrev" (exec "playerctl previous") ''{ locked = true }'')

					# Mouse drag
					(bindo "SUPER + mouse:272" ''hl.dsp.window.drag()'' ''{ drag = true }'')
				];
			};
		extraConfig = ''
			hl.env("XCURSOR_SIZE", "10")
			hl.env("HYPRCURSOR_SIZE", "10")
			hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")
			hl.env("QT_QPA_PLATFORM", "wayland")
			hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
			hl.env("QT_STYLE_OVERRIDE", "Fusion")

			hl.monitor({
			  output = "",
			  mode = "preferred",
			  position = "auto",
			  scale = 1
			})

			hl.config({
			  general = {
			    gaps_in = 5,
			    gaps_out = 5,
			    border_size = 0,
			    ["col.active_border"] = "rgba(78a9ffaa)",
			    ["col.inactive_border"] = "rgba(2c2c2caa)",
			    resize_on_border = true,
			    allow_tearing = true,
			    layout = "master"
			  },
			  decoration = {
			    rounding = 10,
			    active_opacity = 1.0,
			    inactive_opacity = 0.7,
			    fullscreen_opacity = 1.0,
			    shadow = {
			      enabled = true,
			      range = 20,
			      color = "rgba(1a1a1aee)"
			    },
			    blur = {
			      enabled = true,
			      size = 3,
			      passes = 2,
			      brightness = 0.6,
			      contrast = 1.0,
			      noise = 0,
			      xray = false,
			      popups = false
			    }
			  },
			  dwindle = {
			    preserve_split = true
			  },
			  master = {
			    new_status = "master"
			  },
			  misc = {
			    force_default_wallpaper = 0,
			    disable_hyprland_logo = true
			  },
			  input = {
			    kb_layout = "es",
			    kb_variant = "",
			    kb_model = "thinkpad",
			    follow_mouse = 1,
			    sensitivity = 0,
			    touchpad = {
			      natural_scroll = false
			    }
			  }
			})

			hl.device({
			  name = "tpps/2-synaptics-trackpoint",
			  sensitivity = -0.4,
			  scroll_method = "no_scroll"
			})
			hl.device({
			  name = "logitech-pro-x-1",
			  sensitivity = -0.2
			})

			-- Curves
			hl.curve("linear", { type = "bezier", points = { {0, 0}, {1, 1} } })
			hl.curve("snappyReturn", { type = "bezier", points = { {0.4, 0.9}, {0.6, 1.0} } })
			hl.curve("bounce", { type = "bezier", points = { {0.4, 0.9}, {0.6, 1.0} } })
			hl.curve("md3_decel", { type = "bezier", points = { {0.05, 0.7}, {0.1, 1} } })
			hl.curve("softAcDecel", { type = "bezier", points = { {0.26, 0.26}, {0.15, 1} } })

			-- Animations
			hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "snappyReturn", style = "slidevert" })
			hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "bounce", style = "slide" })
			hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "linear" })
			hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "md3_decel" })
			hl.animation({ leaf = "workspaces", enabled = true, speed = 2.5, bezier = "softAcDecel", style = "slide" })

			-- Gestures (3 fingers)
			hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
			hl.gesture({ fingers = 3, direction = "down", action = "close" })
			hl.gesture({ fingers = 3, direction = "up", action = function() hl.exec_cmd("wofi --show drun") end })

			-- Gestures (4 fingers)
			hl.gesture({ fingers = 4, direction = "vertical", action = function() hl.dispatch(hl.dsp.workspace.toggle_special()) end })

			-- Window rules
			hl.window_rule({ name = "suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })
			hl.window_rule({ name = "kitty-float", match = { class = "kitty" }, float = true, size = "800 500", center = true })
			hl.window_rule({ name = "nautilus-float", match = { class = "org.gnome.Nautilus" }, float = true, size = "1000 700", center = true })

			-- Autostart (available programs only)
			hl.on("hyprland.start", function()
			  hl.exec_cmd("waybar")
			end)
		'';
	};
}
