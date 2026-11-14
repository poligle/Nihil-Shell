# hyprland.nix by poligle

{ config, osConfig, pkgs, lib, ... }:
let
	lua = lib.generators.mkLuaInline;
	t = osConfig.nihil.tokens;
	sound = osConfig.nihil.sounds;
	rgb = hex: "rgb(${hex})";

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

	niloBinds = lib.optionals osConfig.nihil.nilo.enable
	[
		(bind "SUPER + SHIFT + code:201" (exec "nihil-ipc nilo toggle"))
	];

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
		overview = ''hl.dsp.global("quickshell:nihil-overview")'';
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
	programBinds = map (program: bind program.keys (exec (lib.escape [ "\\" "\"" ] program.exec)))
		(builtins.filter (program: program.keys != null) osConfig.nihil.programs);

	actionBinds = lib.mapAttrsToList (name: action: bind keys.${name} action)
		(lib.filterAttrs (name: _: keys.${name} or null != null) actions)
		++ lib.optional (keys.screenshot != null)
			(bindWith keys.screenshot (exec "nihil-shot screen") { locked = true; })
		++ lib.optional (keys.snip or null != null)
			(bindWith keys.snip (exec "nihil-shot region") { locked = true; })
		++ lib.optional (keys.screenshot != null && !(hasShift keys.screenshot))
			(bind "SHIFT + ${keys.screenshot}" (exec "nihil-record toggle screen"))
		++ lib.optional (keys.snip or null != null && !(hasShift keys.snip))
			(bind "SHIFT + ${keys.snip}" (exec "nihil-record toggle region"));

	trim = text: let m = builtins.match "[[:space:]]*(.*[^[:space:]])[[:space:]]*" text; in if m == null then "" else lib.head m;
	parts = combo: lib.filter (part: part != "") (map trim (lib.splitString "+" combo));
	hasShift = combo: lib.elem "SHIFT" (map lib.toUpper (parts combo));
	normal = combo: lib.concatStringsSep "+" (lib.sort (a: b: a < b)
		(map (part: let up = lib.toUpper part; in if up == "CONTROL" then "CTRL" else up) (parts combo)));
	takenBy = name: combo: combo != null && lib.elem (normal combo) (map normal (lib.filter (other: other != null)
		(lib.mapAttrsToList (other: value: if other == name then null else value) keys
			++ map (program: program.keys) osConfig.nihil.programs)));
	clipboardKey = keys.clipboard or null;
	copyKey = keys.copy or null;
	clipboardTaken = takenBy "clipboard" clipboardKey;
	copyTaken = takenBy "copy" copyKey;
	clipboardOn = clipboardKey != null && !clipboardTaken;
	copyOn = copyKey != null && !copyTaken;

	modifierKeys =
	{
		SUPER = [ "Super_L" "Super_R" ];
		CTRL = [ "Control_L" "Control_R" ];
		ALT = [ "Alt_L" "Alt_R" ];
		SHIFT = [ "Shift_L" "Shift_R" ];
	};
	modifierAlias = { WIN = "SUPER"; LOGO = "SUPER"; MOD4 = "SUPER"; META = "SUPER"; CONTROL = "CTRL"; MOD1 = "ALT"; };
	firstModifier = mods: let first = if mods == [ ] then "" else lib.toUpper (lib.head mods); in modifierAlias.${first} or first;
	pasteModifier = if clipboardOn then firstModifier (lib.init (parts clipboardKey)) else "";
	modifierSyms = modifierKeys.${pasteModifier} or [ ];

	keyState = mods: key: state: ''hl.dispatch(hl.dsp.send_key_state({ mods = "${mods}", key = "${key}", state = "${state}" }))'';
	clipboardBinds = lib.optional copyOn (bind copyKey ''
		function()
			${keyState "CTRL" "Insert" "down"}
			${keyState "CTRL" "Insert" "up"}
		end
	'');

	pasteMods = if clipboardOn then lib.init (parts clipboardKey) else [ ];
	pasteKey = if clipboardOn then lib.last (parts clipboardKey) else "";
	held = modifierSyms != [ ];
	withMods = mods: key: lib.concatStringsSep " + " (mods ++ [ key ]);
	shifted = key: lib.optional (!lib.elem "SHIFT" (map lib.toUpper pasteMods)) (withMods (pasteMods ++ [ "SHIFT" ]) key);
	historyKeys =
		map (key: { combo = withMods pasteMods key; name = "next"; leave = false; }) [ pasteKey "Tab" "Down" "Right" ]
		++ map (combo: { inherit combo; name = "back"; leave = false; }) (shifted pasteKey ++ shifted "Tab")
		++ map (key: { combo = withMods pasteMods key; name = "back"; leave = false; }) [ "Up" "Left" ]
		++ map (key: { combo = withMods pasteMods key; name = "forget"; leave = false; }) [ "Delete" "BackSpace" ]
		++ map (key: { combo = withMods pasteMods key; name = "paste"; leave = true; }) [ "Return" "KP_Enter" ]
		++ [ { combo = withMods pasteMods "Escape"; name = "cancel"; leave = true; } ];
	overviewKey = keys.overview or null;
	overviewMods = if overviewKey != null then lib.init (parts overviewKey) else [ ];
	overviewLetter = if overviewKey != null then lib.last (parts overviewKey) else "";
	overviewModifier = firstModifier overviewMods;
	overviewHeld = modifierKeys ? ${overviewModifier};
	overviewShifted = key: lib.optional (!lib.elem "SHIFT" (map lib.toUpper overviewMods)) (withMods (overviewMods ++ [ "SHIFT" ]) key);
	overviewKeys =
		map (key: { combo = withMods overviewMods key; name = "next"; leave = false; }) [ overviewLetter "Tab" "Right" ]
		++ map (combo: { inherit combo; name = "back"; leave = false; }) (overviewShifted overviewLetter ++ overviewShifted "Tab")
		++ map (key: { combo = withMods overviewMods key; name = "back"; leave = false; }) [ "Left" ]
		++ map (key: { combo = withMods overviewMods key; name = "go"; leave = true; }) [ "Return" "KP_Enter" ]
		++ [ { combo = withMods overviewMods "Escape"; name = "cancel"; leave = true; } ];

	watched = lib.unique (lib.optional held pasteModifier ++ lib.optional overviewHeld overviewModifier);
	leaves = modifier: lib.optional (held && modifier == pasteModifier) "nihil-clipboard"
		++ lib.optional (overviewHeld && modifier == overviewModifier) "nihil-overview";
	watchBinds = indent: lib.concatMapStringsSep "\n${indent}" (modifier:
		"for _, sym in ipairs({ ${luaList modifierKeys.${modifier}} }) do hl.bind(sym, watcher(${luaString (lib.toLower modifier)}, { ${luaList (leaves modifier)} }), watch) end") watched;
	submapKeys = prefix: list: lib.concatMapStringsSep "\n\t\t\t\t" (k: "key(${luaString k.combo}, ${luaString "${prefix}-${k.name}"}, ${lib.boolToString k.leave})") list;

	luaString = builtins.toJSON;
	luaList = lib.concatMapStringsSep ", " luaString;
	holdLua = ''
		do
			local function say(name)
				hl.dispatch(hl.dsp.global("quickshell:nihil-" .. name))
			end
	'' + lib.optionalString clipboardOn ''
			hl.bind(${luaString clipboardKey}, function()
				say("clipboard")
				${lib.optionalString held ''hl.dispatch(hl.dsp.submap("nihil-clipboard"))''}
			end)
	'' + lib.optionalString (watched != [ ]) ''
			local function watcher(name, submaps)
				return function()
					say(name)
					local now = hl.get_current_submap()
					for _, submap in ipairs(submaps) do
						if now == submap then
							hl.dispatch(hl.dsp.submap("reset"))
						end
					end
				end
			end
			local watch = { ignore_mods = true, transparent = true, non_consuming = true, dont_inhibit = true, locked = true }
			${watchBinds "\t\t\t"}
	'' + lib.optionalString held ''
			hl.define_submap("nihil-clipboard", function()
				local function key(combo, name, leave)
					hl.bind(combo, function()
						say(name)
						if leave then
							hl.dispatch(hl.dsp.submap("reset"))
						end
					end)
				end
				${submapKeys "clipboard" historyKeys}
				${watchBinds "\t\t\t\t"}
			end)
	'' + lib.optionalString overviewHeld ''
			hl.define_submap("nihil-overview", function()
				local function key(combo, name, leave)
					hl.bind(combo, function()
						say(name)
						if leave then
							hl.dispatch(hl.dsp.submap("reset"))
						end
					end)
				end
				${submapKeys "overview" overviewKeys}
				${watchBinds "\t\t\t\t"}
			end)
	'' + ''
		end
	'';

	fingers = osConfig.nihil.gestures;

	maximizeGesture = spread: ''
		function()
			local window = hl.get_active_window()
			local state = window and window.fullscreen or 0
			if window and ${if spread then "state == 0" else "state ~= 0"} then
				hl.exec_cmd("${playSound sound.fullscreen}")
				hl.dispatch(hl.dsp.window.fullscreen({ mode = ${if spread then ''"maximized"'' else ''state == 1 and "maximized" or "fullscreen"''} }))
			end
		end
	'';

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
	stylix.targets.hyprland.enable = false;

	warnings = lib.optional clipboardTaken
		"NIHIL: ${clipboardKey}, the paste and clipboard history key, is taken by another action or program: give it another in Preferences, Shortcuts."
		++ lib.optional copyTaken
		"NIHIL: ${copyKey}, the copy key, is taken by another action or program: give it another in Preferences, Shortcuts.";

	wayland.windowManager.hyprland =
	{
		enable = true;
		package = null;
		portalPackage = null;
		configType = "lua";
		extraConfig = lib.optionalString (clipboardOn || overviewHeld) holdLua;

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

			env = lib.mapAttrsToList envVar (import ./session-env.nix);

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

			gesture = lib.filter (gesture: gesture.fingers != null)
			[
				{ fingers = fingers.workspaces; direction = "horizontal"; action = "workspace"; }
				{ fingers = fingers.close; direction = "down"; action = "close"; }
				{ fingers = fingers.launcher; direction = "up"; action = lua ''function() hl.exec_cmd("nihil-ipc drawers toggle launcher") end''; }
				{ fingers = fingers.maximize; direction = "pinchout"; action = lua (maximizeGesture true); }
				{ fingers = fingers.maximize; direction = "pinchin"; action = lua (maximizeGesture false); }
				{ fingers = fingers.special; direction = "vertical"; action = lua (withSound sound.special "hl.dsp.workspace.toggle_special()"); }
			];

			window_rule =
			[
				{ name = "suppress-maximize"; match.class = ".*"; suppress_event = "maximize"; }
				{ name = "kitty-float"; match.class = "kitty"; float = true; size = "800 500"; center = true; }
				{ name = "thunar-float"; match.class = "thunar"; float = true; center = true; }
				{ name = "thunar-size"; match.class = "thunar"; match.title = ".+ - Thunar"; size = "1000 700"; }
				(floatingPanel "wifi-float" "nm-connection-editor")
				(floatingPanel "bluetooth-float" ".*blueman-manager.*")
				(floatingPanel "vol-float" "org.pulseaudio.pavucontrol")
			];

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
