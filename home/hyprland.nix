# hyprland.nix by poligle

{ config, pkgs, lib, ... }:
let
	lua = lib.generators.mkLuaInline;

	internalPanel = "eDP-1";
	verticalPanel = "DP-1";
	playSound = file: "${pkgs.pipewire}/bin/pw-play --volume 0.4 ${file}";

	bind = key: action: { _args = [ key (lua action) ]; };
	bindWith = key: action: options: { _args = [ key (lua action) options ]; };
	exec = command: ''hl.dsp.exec_cmd("${command}")'';
	withSound = file: action: ''function() hl.exec_cmd("${playSound file}") hl.dispatch(${action}) end'';
	focusWorkspace = workspace: ''hl.dsp.focus({ workspace = "${workspace}" })'';
	moveToWorkspace = workspace: ''hl.dsp.window.move({ workspace = "${workspace}" })'';

	workspaceBinds = lib.concatMap
	(
		number:
		let
			key = toString (lib.mod number 10);
			workspace = toString number;
		in
		[
			(bind "SUPER + ${key}" (focusWorkspace workspace))
			(bind "SUPER + SHIFT + ${key}" (moveToWorkspace workspace))
		]
	)
	(lib.range 1 10);

	envVar = name: value: { _args = [ name value ]; };
	bezier = name: points: { _args = [ name { type = "bezier"; inherit points; } ]; };
	onEvent = event: handler: { _args = [ event (lua handler) ]; };
	soundOn = event: file: onEvent event ''function() hl.exec_cmd("${playSound file}") end'';

	floatingPanel = name: class:
	{
		inherit name;
		match.class = class;
		float = true;
		size = "640 400";
		move = "1270 50";
	};

	lidClose = ''
		function()
			local docked = false
			for _, monitor in ipairs(hl.get_monitors()) do
				if monitor.name ~= "${internalPanel}" then
					docked = true
				end
			end
			if docked then
				hl.monitor({ output = "${internalPanel}", disabled = true })
			else
				hl.exec_cmd("loginctl lock-session")
				hl.dispatch(hl.dsp.dpms({ action = "off", monitor = "${internalPanel}" }))
			end
		end
	'';

	lidOpen = ''
		function()
			hl.monitor({ output = "${internalPanel}", disabled = false })
			hl.dispatch(hl.dsp.dpms({ action = "on" }))
		end
	'';

	autostart = ''
		function()
			hl.exec_cmd("waybar")
			hl.exec_cmd("lxqt-policykit-agent")
			hl.exec_cmd("nm-applet --indicator")
			hl.exec_cmd("waybar-autohide")
			hl.exec_cmd("mic-led-sync")
			hl.exec_cmd("awww img ${config.stylix.image}")
			hl.exec_cmd("eww open-many window-clock window-network window-media")
		end
	'';
in
{
	stylix.targets.hyprland.hyprpaper.enable = false;

	wayland.windowManager.hyprland =
	{
		enable = true;
		package = null;
		portalPackage = null;
		configType = "lua";

		settings =
		{
			env =
			[
				(envVar "QT_QPA_PLATFORM" "wayland")
				(envVar "QT_QPA_PLATFORMTHEME" "qt6ct")
				(envVar "QT_STYLE_OVERRIDE" "Fusion")
			];

			monitor =
			[
				{ output = "HDMI-A-1"; mode = "preferred"; position = "0x0"; scale = 1; transform = 0; }
				{ output = verticalPanel; mode = "1920x1080@165"; position = "2560x-240"; scale = 1; transform = 3; }
				{ output = internalPanel; mode = "preferred"; position = "auto"; scale = 1; transform = 0; disabled = false; }
			];

			config =
			{
				general =
				{
					gaps_in = 5;
					gaps_out = 5;
					border_size = 0;
					resize_on_border = true;
					allow_tearing = false;
					layout = "master";
				};

				decoration =
				{
					rounding = 10;
					active_opacity = 1.0;
					inactive_opacity = 0.7;
					fullscreen_opacity = 1.0;

					shadow =
					{
						enabled = true;
						range = 15;
						color = lib.mkForce "rgba(19191966)";
					};

					blur =
					{
						enabled = true;
						size = 3;
						passes = 2;
						brightness = 0.6;
						contrast = 1.0;
						noise = 0;
						xray = false;
						popups = false;
					};
				};

				dwindle.preserve_split = true;
				master.new_status = "master";

				misc =
				{
					force_default_wallpaper = 0;
					disable_hyprland_logo = true;
				};

				input =
				{
					kb_layout = "es";
					kb_variant = "";
					kb_model = "thinkpad";
					follow_mouse = 1;
					sensitivity = 0;
					touchpad.natural_scroll = false;
				};
			};

			device =
			[
				{ name = "tpps/2-synaptics-trackpoint"; sensitivity = -0.4; scroll_method = "no_scroll"; }
				{ name = "logitech-pro-x-1"; sensitivity = -0.2; }
			];

			curve =
			[
				(bezier "linear" [ [ 0 0 ] [ 1 1 ] ])
				(bezier "snappyReturn" [ [ 0.4 0.9 ] [ 0.6 1.0 ] ])
				(bezier "bounce" [ [ 0.4 0.9 ] [ 0.6 1.0 ] ])
				(bezier "md3_decel" [ [ 0.05 0.7 ] [ 0.1 1 ] ])
				(bezier "softAcDecel" [ [ 0.26 0.26 ] [ 0.15 1 ] ])
			];

			animation =
			[
				{ leaf = "windows"; enabled = true; speed = 5; bezier = "snappyReturn"; style = "slidevert"; }
				{ leaf = "windowsMove"; enabled = true; speed = 4; bezier = "bounce"; style = "slide"; }
				{ leaf = "border"; enabled = true; speed = 10; bezier = "linear"; }
				{ leaf = "fade"; enabled = true; speed = 3; bezier = "md3_decel"; }
				{ leaf = "workspaces"; enabled = true; speed = 2.5; bezier = "softAcDecel"; style = "slide"; }
			];

			gesture =
			[
				{ fingers = 3; direction = "horizontal"; action = "workspace"; }
				{ fingers = 3; direction = "down"; action = "close"; }
				{ fingers = 3; direction = "up"; action = lua ''function() hl.exec_cmd("wofi-open") end''; }
				{ fingers = 4; direction = "vertical"; action = lua (withSound ../sounds/special.ogg "hl.dsp.workspace.toggle_special()"); }
			];

			window_rule =
			[
				{ name = "suppress-maximize"; match.class = ".*"; suppress_event = "maximize"; }
				{ name = "kitty-float"; match.class = "kitty"; float = true; size = "800 500"; center = true; }
				{ name = "thunar-float"; match.class = "thunar"; float = true; size = "1000 700"; center = true; }
				(floatingPanel "wifi-float" "nm-connection-editor")
				(floatingPanel "bluetooth-float" ".*blueman-manager.*")
				(floatingPanel "vol-float" "org.pulseaudio.pavucontrol")
			];

			bind =
			[
				(bind "SUPER + Super_L" (exec "kitty"))
				(bind "SUPER + Space" (exec "wofi-open"))
				(bind "SUPER + E" (exec "thunar"))
				(bind "SUPER + X" (exec "zen-beta"))
				(bind "SUPER + N" (exec "obsidian"))
				(bind "SUPER + C" (exec "code"))
				(bind "SUPER + S" (exec "spotify"))
				(bind "SUPER + A" (exec "aseprite"))
				(bind "SUPER + H" (exec "hyprpicker -a"))
				(bind "SUPER + K" (exec "lock-screen"))

				(bind "SUPER + Q" "hl.dsp.window.close()")
				(bind "SUPER + V" ''hl.dsp.window.float({ action = "toggle" })'')
				(bind "SUPER + F" (withSound ../sounds/fullscreen.ogg ''hl.dsp.window.fullscreen({ mode = "maximized" })''))
				(bind "SUPER + SHIFT + F" (withSound ../sounds/fullscreen.ogg ''hl.dsp.window.fullscreen({ mode = "fullscreen" })''))

				(bind "SUPER + left" ''hl.dsp.focus({ direction = "left" })'')
				(bind "SUPER + right" ''hl.dsp.focus({ direction = "right" })'')
				(bind "SUPER + up" ''hl.dsp.focus({ direction = "up" })'')
				(bind "SUPER + down" ''hl.dsp.focus({ direction = "down" })'')

				(bind "SUPER + Escape" (withSound ../sounds/special.ogg "hl.dsp.workspace.toggle_special()"))
				(bind "SUPER + Control_L" ''hl.dsp.window.move({ workspace = "special" })'')
				(bind "SUPER + Tab" ''hl.dsp.focus({ workspace = "e+1" })'')

				(bindWith "XF86AudioRaiseVolume" (exec "osd-volume up") { locked = true; repeating = true; })
				(bindWith "XF86AudioLowerVolume" (exec "osd-volume down") { locked = true; repeating = true; })
				(bindWith "XF86AudioMute" (exec "osd-volume mute") { locked = true; })
				(bindWith "XF86AudioMicMute" (exec "sh -c 'wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle; mic-led-sync'") { locked = true; })
				(bindWith "XF86MonBrightnessUp" (exec "osd-brightness up") { locked = true; repeating = true; })
				(bindWith "XF86MonBrightnessDown" (exec "osd-brightness down") { locked = true; repeating = true; })

				(bindWith "PRINT" (exec "hyprshot -m output --clipboard-only") { locked = true; })
				(bindWith "XF86SelectiveScreenshot" (exec "hyprshot -m region --clipboard-only") { locked = true; })
				(bindWith "XF86AudioNext" (exec "playerctl next") { locked = true; })
				(bindWith "XF86AudioPause" (exec "playerctl play-pause") { locked = true; })
				(bindWith "XF86AudioPlay" (exec "playerctl play-pause") { locked = true; })
				(bindWith "XF86AudioPrev" (exec "playerctl previous") { locked = true; })

				(bind "mouse:275" ''hl.dsp.focus({ workspace = "e-1" })'')
				(bind "mouse:276" ''hl.dsp.focus({ workspace = "e+1" })'')
				(bindWith "SUPER + mouse:272" "hl.dsp.window.drag()" { drag = true; })
				(bindWith "mouse:274" "hl.dsp.window.drag()" { drag = true; })

				(bindWith "switch:on:Lid Switch" lidClose { locked = true; })
				(bindWith "switch:off:Lid Switch" lidOpen { locked = true; })
			]
			++ workspaceBinds;

			on =
			[
				(onEvent "hyprland.start" autostart)
				(soundOn "workspace.active" ../sounds/switch.ogg)
				(soundOn "window.open" ../sounds/open.ogg)
				(soundOn "window.close" ../sounds/close.ogg)
			];
		};
	};
}
