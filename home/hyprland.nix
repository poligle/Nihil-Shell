# hyprland.nix by poligle

{ config, osConfig, pkgs, lib, ... }:
let
	lua = lib.generators.mkLuaInline;
	t = osConfig.nihil.tokens;
	sound = osConfig.nihil.sounds;
	rgb = hex: "rgb(${hex})";

	internalPanel = "eDP-1";
	verticalPanel = "DP-1";
	playSound = file: "${pkgs.pipewire}/bin/pw-play --volume 0.4 ${file}";

	bind = key: action: { _args = [ key (lua action) ]; };
	bindWith = key: action: options: { _args = [ key (lua action) options ]; };
	exec = command: ''hl.dsp.exec_cmd("${command}")'';
	withSound = file: action: ''function() hl.exec_cmd("${playSound file}") hl.dispatch(${action}) end'';
	focusWorkspace = workspace: ''hl.dsp.focus({ workspace = "${workspace}" })'';
	moveToWorkspace = workspace: ''hl.dsp.window.move({ workspace = "${workspace}" })'';

	# Nilo (modules/nilo.nix). The Copilot key sends SUPER + SHIFT + F23
	# (Linux 6.14 and later), which xkb names XF86TouchpadOff.
	niloBinds = lib.optionals osConfig.nihil.nilo.enable
	[
		(bind "SUPER + I" (exec "nihil-ipc nilo toggle"))
		(bind "SUPER + SHIFT + XF86TouchpadOff" (exec "nihil-ipc nilo toggle"))
	];

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

	keepLidState = ''
		function()
			if not lidIsClosed() then
				return
			end
			for _, monitor in ipairs(hl.get_monitors()) do
				if monitor.name ~= "${internalPanel}" then
					hl.monitor({ output = "${internalPanel}", disabled = true })
					return
				end
			end
		end
	'';

	autostart = ''
		function()
			(${keepLidState})()
			hl.exec_cmd("lxqt-policykit-agent")
			hl.exec_cmd("nm-applet --indicator")
			hl.exec_cmd("mic-led-sync")
			hl.exec_cmd("nihil-wallpaper restore")
		end
	'';
in
{
	# NIHIL owns every colour here (and awww the wallpaper), so Stylix stays out.
	stylix.targets.hyprland.enable = false;

	wayland.windowManager.hyprland =
	{
		enable = true;
		package = null;
		portalPackage = null;
		configType = "lua";

		settings =
		{
			lidIsClosed =
			{
				_var = lua ''
					function()
						local handle = io.popen("${pkgs.coreutils}/bin/cat /proc/acpi/button/lid/*/state 2>/dev/null")
						if not handle then
							return false
						end
						local state = handle:read("*a") or ""
						handle:close()
						return state:find("closed") ~= nil
					end
				'';
			};

			# Shared with the shell, for the apps opened from the launcher.
			env = lib.mapAttrsToList envVar (import ./session-env.nix);

			monitor =
			[
				{ output = "HDMI-A-1"; mode = "preferred"; position = "0x0"; scale = 1; transform = 0; }
				{ output = verticalPanel; mode = "1920x1080@165"; position = "2560x-240"; scale = 1; transform = 3; }
				{ output = internalPanel; mode = "preferred"; position = "auto"; scale = 1; transform = 0; disabled = false; }
			];

			workspace_rule =
			[
				{ workspace = "m[${verticalPanel}]"; layout_opts.orientation = "top"; }
			];

			config =
			{
				general =
				{
					gaps_in = t.windows.gapsIn;
					gaps_out = t.windows.gapsOut;
					border_size = t.windows.border;
					col =
					{
						active_border = rgb t.palette.muted;
						inactive_border = rgb t.palette.line;
					};
					resize_on_border = true;
					allow_tearing = false;
					layout = "master";
				};

				# Flat, like the frame: hairline borders instead of shadows.
				decoration =
				{
					rounding = t.windows.rounding;
					active_opacity = 1.0;
					inactive_opacity = 0.85;
					fullscreen_opacity = 1.0;

					shadow.enabled = false;

					blur =
					{
						enabled = true;
						size = 4;
						passes = 2;
						brightness = 0.5;
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

			# NIHIL motion: decisive deceleration, never a bounce.
			curve =
			[
				(bezier "linear" [ [ 0 0 ] [ 1 1 ] ])
				(bezier "nihilOut" [ [ 0.05 0.7 ] [ 0.1 1.0 ] ])
				(bezier "nihilInOut" [ [ 0.4 0.0 ] [ 0.2 1.0 ] ])
			];

			animation =
			[
				{ leaf = "windows"; enabled = true; speed = 2.6; bezier = "nihilOut"; style = "popin 94%"; }
				{ leaf = "windowsMove"; enabled = true; speed = 2.4; bezier = "nihilOut"; style = "slide"; }
				{ leaf = "border"; enabled = true; speed = 4; bezier = "linear"; }
				{ leaf = "fade"; enabled = true; speed = 2; bezier = "nihilOut"; }
				{ leaf = "workspaces"; enabled = true; speed = 3; bezier = "nihilInOut"; style = "slide"; }
			];

			gesture =
			[
				{ fingers = 3; direction = "horizontal"; action = "workspace"; }
				{ fingers = 3; direction = "down"; action = "close"; }
				{ fingers = 3; direction = "up"; action = lua ''function() hl.exec_cmd("nihil-ipc drawers toggle launcher") end''; }
				{ fingers = 4; direction = "vertical"; action = lua (withSound sound.special "hl.dsp.workspace.toggle_special()"); }
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

			# The NIHIL shell animates its own surfaces (frame, drawers, widgets).
			layer_rule =
			[
				{ name = "nihil-shell"; match.namespace = "^nihil-.*$"; no_anim = true; }
			];

			bind =
			[
				(bind "SUPER + Super_L" (exec "kitty"))
				(bind "SUPER + Space" (exec "nihil-ipc drawers toggle launcher"))
				(bind "SUPER + D" (exec "nihil-ipc drawers toggle dashboard"))
				(bind "SUPER + P" (exec "nihil-ipc drawers toggle panel"))
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
				(bind "SUPER + F" (withSound sound.fullscreen ''hl.dsp.window.fullscreen({ mode = "maximized" })''))
				(bind "SUPER + SHIFT + F" (withSound sound.fullscreen ''hl.dsp.window.fullscreen({ mode = "fullscreen" })''))

				(bind "SUPER + left" ''hl.dsp.focus({ direction = "left" })'')
				(bind "SUPER + right" ''hl.dsp.focus({ direction = "right" })'')
				(bind "SUPER + up" ''hl.dsp.focus({ direction = "up" })'')
				(bind "SUPER + down" ''hl.dsp.focus({ direction = "down" })'')

				(bind "SUPER + Escape" (withSound sound.special "hl.dsp.workspace.toggle_special()"))
				(bind "SUPER + Control_L" ''hl.dsp.window.move({ workspace = "special" })'')
				(bind "SUPER + Tab" ''hl.dsp.focus({ workspace = "e+1" })'')

				(bindWith "XF86AudioRaiseVolume" (exec "osd-volume up") { locked = true; repeating = true; })
				(bindWith "XF86AudioLowerVolume" (exec "osd-volume down") { locked = true; repeating = true; })
				(bindWith "XF86AudioMute" (exec "osd-volume mute") { locked = true; })
				(bindWith "XF86AudioMicMute" (exec "osd-mic") { locked = true; })
				(bindWith "XF86MonBrightnessUp" (exec "osd-brightness up") { locked = true; repeating = true; })
				(bindWith "XF86MonBrightnessDown" (exec "osd-brightness down") { locked = true; repeating = true; })

				(bindWith "PRINT" (exec "hyprshot -m region --clipboard-only") { locked = true; })
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
			++ niloBinds
			++ workspaceBinds;

			on =
			[
				(onEvent "hyprland.start" autostart)
				(onEvent "config.reloaded" keepLidState)
				(onEvent "monitor.added" ''function() (${keepLidState})() hl.exec_cmd("nihil-wallpaper restore") end'')
				(soundOn "workspace.active" sound.switch)
				(soundOn "window.open" sound.open)
				(soundOn "window.close" sound.close)
			];
		};
	};
}
