# hyprland.nix by poligle

{ config, osConfig, pkgs, lib, ... }:
let
	lua = lib.generators.mkLuaInline;
	t = osConfig.nihil.tokens;
	sound = osConfig.nihil.sounds;
	rgb = hex: "rgb(${hex})";

	# Screens come from the machine's settings (nihil.outputs): a laptop's
	# own panel is the one called eDP, and the ones turned on their side
	# stack their windows from the top.
	outputs = osConfig.nihil.outputs;
	panels = lib.filter (lib.hasPrefix "eDP") (builtins.attrNames outputs);
	internalPanel = if panels != [ ] then lib.head panels else "eDP-1";
	verticalOutputs = builtins.attrNames (lib.filterAttrs (_: output: lib.elem output.transform [ 1 3 5 7 ]) outputs);
	xkb = osConfig.services.xserver.xkb;
	playSound = file: "${pkgs.pipewire}/bin/pw-play --volume 0.4 ${file}";

	bind = key: action: { _args = [ key (lua action) ]; };
	bindWith = key: action: options: { _args = [ key (lua action) options ]; };
	exec = command: ''hl.dsp.exec_cmd("${command}")'';
	withSound = file: action: ''function() hl.exec_cmd("${playSound file}") hl.dispatch(${action}) end'';
	focusWorkspace = workspace: ''hl.dsp.focus({ workspace = "${workspace}" })'';
	moveToWorkspace = workspace: ''hl.dsp.window.move({ workspace = "${workspace}" })'';

	# Nilo (modules/nilo.nix). The Copilot key sends SUPER + SHIFT + F23
	# (Linux 6.14 and later). Its name depends on xkeyboard-config (recent
	# ones say XF86Assistant, older ones XF86TouchpadOff), so the bind goes
	# by the keycode wev shows: 201. One bind only, or a press would toggle twice.
	niloBinds = lib.optionals osConfig.nihil.nilo.enable
	[
		(bind "SUPER + SHIFT + code:201" (exec "nihil-ipc nilo toggle"))
	];

	# NIHIL's actions, on the keys the machine gives them (nihil.binds,
	# modules/binds.nix): an action with null has no bind.
	keys = osConfig.nihil.binds;
	actions =
	{
		launcher = exec "nihil-ipc drawers toggle launcher";
		dashboard = exec "nihil-ipc drawers toggle dashboard";
		panel = exec "nihil-ipc drawers toggle panel";
		colourPicker = exec "hyprpicker -a";
		lock = exec "lock-screen";
		settings = exec "nihil-ipc settings toggle";
		wallpapers = exec "nihil-ipc drawers toggle wallpapers";
		close = "hl.dsp.window.close()";
		float = ''hl.dsp.window.float({ action = "toggle" })'';
		maximize = withSound sound.fullscreen ''hl.dsp.window.fullscreen({ mode = "maximized" })'';
		fullscreen = withSound sound.fullscreen ''hl.dsp.window.fullscreen({ mode = "fullscreen" })'';
		special = withSound sound.special "hl.dsp.workspace.toggle_special()";
		toSpecial = ''hl.dsp.window.move({ workspace = "special" })'';
		nextWorkspace = ''hl.dsp.focus({ workspace = "e+1" })'';
	} // lib.optionalAttrs osConfig.nihil.nilo.enable
	{
		nilo = exec "nihil-ipc nilo toggle";
	};
	# Programs: a command each, quoted for Lua.
	programBinds = map (program: bind program.keys (exec (lib.escape [ "\\" "\"" ] program.exec)))
		(builtins.filter (program: program.keys != null) osConfig.nihil.programs);

	actionBinds = lib.mapAttrsToList (name: action: bind keys.${name} action)
		(lib.filterAttrs (name: _: keys.${name} or null != null) actions)
		++ lib.optional (keys.screenshot != null)
			(bindWith keys.screenshot (exec "hyprshot -m region --clipboard-only") { locked = true; });

	# The clipboard history (home/clipboard.nix, services/Clipboard.qml): its
	# key only brings it out, and the shell does the rest with the keyboard.
	# The key again goes on to the next copy, and letting go of its modifier
	# pastes the one chosen. A release bind can't see that modifier go up:
	# Hyprland skips one whose key went down before its submap, or that took
	# part in another bind, and the modifier is always both (ngrayson/nixos
	# #228, on 0.55.4). Not bound when the history is off, or when an action
	# or a program already has its key (a warning says so).
	trim = text: let m = builtins.match "[[:space:]]*(.*[^[:space:]])[[:space:]]*" text; in if m == null then "" else lib.head m;
	parts = combo: lib.filter (part: part != "") (map trim (lib.splitString "+" combo));
	normal = combo: lib.concatStringsSep "+" (lib.sort (a: b: a < b)
		(map (part: let up = lib.toUpper part; in if up == "CONTROL" then "CTRL" else up) (parts combo)));
	clipboardKey = keys.clipboard or null;
	clipboardTaken = clipboardKey != null && lib.elem (normal clipboardKey) (map normal (lib.filter (combo: combo != null)
		(lib.mapAttrsToList (name: combo: if name == "clipboard" then null else combo) keys
			++ map (program: program.keys) osConfig.nihil.programs)));
	clipboardBinds = lib.optional (osConfig.nihil.clipboard > 0 && clipboardKey != null && !clipboardTaken)
		(bind clipboardKey (exec "nihil-ipc clipboard open"));

	fingers = osConfig.nihil.gestures;

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

	# The lid. Closed with another screen on, the laptop's panel goes off and
	# the session stays on the other one (logind leaves a docked laptop
	# awake, modules/hardware.nix). Closed without one, logind suspends it:
	# this only locks and darkens the panel in the meantime.
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

	warnings = lib.optional (osConfig.nihil.clipboard > 0 && clipboardTaken)
		"NIHIL: ${clipboardKey}, the clipboard history's key, is taken by another action or program: give it another in Preferences, Shortcuts.";

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

			# Screens not in the settings get Hyprland's own: preferred, auto, 1.
			monitor = lib.mapAttrsToList (name: output:
			{
				inherit (output) mode position scale transform;
				output = name;
			} // lib.optionalAttrs (name == internalPanel) { disabled = false; }) outputs;

			workspace_rule = map (name: { workspace = "m[${name}]"; layout_opts.orientation = "top"; }) verticalOutputs;

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
					kb_layout = xkb.layout;
					kb_variant = xkb.variant;
					kb_model = xkb.model;
					follow_mouse = 1;
					sensitivity = 0;
					touchpad.natural_scroll = false;
				};
			};

			# Per-device input settings belong to the machine, in its home.nix:
			# wayland.windowManager.hyprland.settings.device = [ … ];

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

			# Each gesture with the fingers the machine gives it (nihil.gestures).
			gesture = lib.filter (gesture: gesture.fingers != null)
			[
				{ fingers = fingers.workspaces; direction = "horizontal"; action = "workspace"; }
				{ fingers = fingers.close; direction = "down"; action = "close"; }
				{ fingers = fingers.launcher; direction = "up"; action = lua ''function() hl.exec_cmd("nihil-ipc drawers toggle launcher") end''; }
				{ fingers = fingers.special; direction = "vertical"; action = lua (withSound sound.special "hl.dsp.workspace.toggle_special()"); }
			];

			window_rule =
			[
				{ name = "suppress-maximize"; match.class = ".*"; suppress_event = "maximize"; }
				{ name = "kitty-float"; match.class = "kitty"; float = true; size = "800 500"; center = true; }
				# Every Thunar window floats; only the main ones ("Downloads - Thunar")
				# get the size, so its dialogs (rename, progress) keep their own.
				{ name = "thunar-float"; match.class = "thunar"; float = true; center = true; }
				{ name = "thunar-size"; match.class = "thunar"; match.title = ".+ - Thunar"; size = "1000 700"; }
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
				(bind "SUPER + left" ''hl.dsp.focus({ direction = "left" })'')
				(bind "SUPER + right" ''hl.dsp.focus({ direction = "right" })'')
				(bind "SUPER + up" ''hl.dsp.focus({ direction = "up" })'')
				(bind "SUPER + down" ''hl.dsp.focus({ direction = "down" })'')

				(bindWith "XF86AudioRaiseVolume" (exec "osd-volume up") { locked = true; repeating = true; })
				(bindWith "XF86AudioLowerVolume" (exec "osd-volume down") { locked = true; repeating = true; })
				(bindWith "XF86AudioMute" (exec "osd-volume mute") { locked = true; })
				(bindWith "XF86AudioMicMute" (exec "osd-mic") { locked = true; })
				(bindWith "XF86MonBrightnessUp" (exec "osd-brightness up") { locked = true; repeating = true; })
				(bindWith "XF86MonBrightnessDown" (exec "osd-brightness down") { locked = true; repeating = true; })

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
			++ actionBinds
			++ clipboardBinds
			++ programBinds
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
