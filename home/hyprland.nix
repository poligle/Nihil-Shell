{ config, pkgs, lib, ... }:
{
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
					(bind "SUPER + Space" (exec "wofi --show drun"))
					(bind "SUPER + E" (exec "thunar"))
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
					(bind "SUPER + Control_L" ''hl.dsp.window.move({ workspace = "special" })'')

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
					(bind "SUPER + Tab" ''hl.dsp.focus({ workspace = "e+1" })'')

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

					# Volume (wpctl, capped at 100%)
					(bindo "XF86AudioRaiseVolume" (exec "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+") ''{ locked = true, repeating = true }'')
					(bindo "XF86AudioLowerVolume" (exec "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-") ''{ locked = true, repeating = true }'')
					(bindo "XF86AudioMute" (exec "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle") ''{ locked = true }'')
					(bindo "XF86AudioMicMute" (exec "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle") ''{ locked = true }'')

					# Brightness (brightnessctl)
					(bindo "XF86MonBrightnessUp" (exec "brightnessctl set 5%+") ''{ locked = true, repeating = true }'')
					(bindo "XF86MonBrightnessDown" (exec "brightnessctl set 5%-") ''{ locked = true, repeating = true }'')

					# Multimedia keys (not installed yet - commented)
					# (bindo "PRINT" (exec "hyprshot -m output --clipboard-only") ''{ locked = true }'')
					# (bindo "F10" (exec "hyprshot -m region --clipboard-only") ''{ locked = true }'')
					# (bindo "XF86AudioNext" (exec "playerctl next") ''{ locked = true }'')
					# (bindo "XF86AudioPause" (exec "playerctl play-pause") ''{ locked = true }'')
					# (bindo "XF86AudioPlay" (exec "playerctl play-pause") ''{ locked = true }'')
					# (bindo "XF86AudioPrev" (exec "playerctl previous") ''{ locked = true }'')

					# Switch workspaces with mouse side buttons
					(bind "mouse:275" ''hl.dsp.focus({ workspace = "e-1" })'')
					(bind "mouse:276" ''hl.dsp.focus({ workspace = "e+1" })'')

					# Move windows with mouse drag
					(bindo "SUPER + mouse:272" ''hl.dsp.window.drag()'' ''{ drag = true }'')
					(bindo "mouse:274" ''hl.dsp.window.drag()'' ''{ drag = true }'')
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
			hl.curve("linear", { type = "bezier", points = { {0, 0}, {1, 1} } })
			hl.curve("snappyReturn", { type = "bezier", points = { {0.4, 0.9}, {0.6, 1.0} } })
			hl.curve("bounce", { type = "bezier", points = { {0.4, 0.9}, {0.6, 1.0} } })
			hl.curve("md3_decel", { type = "bezier", points = { {0.05, 0.7}, {0.1, 1} } })
			hl.curve("softAcDecel", { type = "bezier", points = { {0.26, 0.26}, {0.15, 1} } })
			hl.animation({ leaf = "windows", enabled = true, speed = 5, bezier = "snappyReturn", style = "slidevert" })
			hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, bezier = "bounce", style = "slide" })
			hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "linear" })
			hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "md3_decel" })
			hl.animation({ leaf = "workspaces", enabled = true, speed = 2.5, bezier = "softAcDecel", style = "slide" })
			hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
			hl.gesture({ fingers = 3, direction = "down", action = "close" })
			hl.gesture({ fingers = 3, direction = "up", action = function() hl.exec_cmd("wofi --show drun") end })
			hl.gesture({ fingers = 4, direction = "vertical", action = function() hl.dispatch(hl.dsp.workspace.toggle_special()) end })

			-- Window rules
			hl.window_rule({ name = "suppress-maximize", match = { class = ".*" }, suppress_event = "maximize" })
			hl.window_rule({ name = "kitty-float", match = { class = "kitty" }, float = true, size = "800 500", center = true })
			hl.window_rule({ name = "thunar-float", match = { class = "thunar" }, float = true, size = "1000 700", center = true })
			hl.window_rule({ name = "wifi-float", match = { class = "nm-connection-editor" }, float = true, size = "640 400", move = "1270 50" })
			hl.window_rule({ name = "bluetooth-float", match = { class = "blueman-manager" }, float = true, size = "640 400", move = "1270 50" })
			hl.window_rule({ name = "vol-float", match = { class = "org.pulseaudio.pavucontrol" }, float = true, size = "640 400", move = "1270 50" })

			hl.on("hyprland.start", function()
			  hl.exec_cmd("waybar")
			  hl.exec_cmd("lxqt-policykit-agent")
			  hl.exec_cmd("awww-daemon")
			  hl.exec_cmd("dunst")
			end)
		'';
	};
}
