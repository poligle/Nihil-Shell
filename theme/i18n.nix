# i18n.nix by poligle
#
# Every user-facing string of this configuration, per language. The host
# picks one with `nihil.language`; the shell gets it as a generated Lang.qml
# singleton, and hyprlock, ReGreet and the scripts read `nihil.strings`.
# Both languages must have the same keys (modules/nihil.nix checks it).
#
# `%1` and `%2` are placeholders (QML: Lang.connectedTo.arg(ssid)). Date
# formats use Qt's syntax and are applied with the language's own locale, so
# day and month names follow the language, not the system locale; lockDate is
# a date(1) format for hyprlock, run with LC_TIME=lockLocale.

{
	es =
	{
		locale = "es_ES";
		dateLong = "dddd, d 'de' MMMM";
		dateShort = "d 'de' MMMM";
		dayName = "dddd";
		lockDate = "%a · %d %b";
		lockLocale = "es_ES.UTF-8";

		# hyprlock and greeter
		password = "CONTRASEÑA";
		authFailed = "ERROR · $ATTEMPTS";
		fingerprintReady = "TOCA EL SENSOR";
		fingerprintPresent = "LEYENDO HUELLA";
		welcome = "Bienvenido";

		# launcher
		search = "BUSCAR";
		appsCount = "%1 apps";
		actions = "acciones";
		calculator = "calculadora";
		typeExpression = "escribe una operación";
		enterAgain = "enter otra vez";
		hintApps = "enter abre · > acciones · = calcular · esc cierra";
		hintCalc = "enter copia el resultado · esc cierra";
		actLock = "Bloquear";
		actSuspend = "Suspender";
		actReboot = "Reiniciar";
		actPowerOff = "Apagar";
		actLogout = "Cerrar sesión";
		actNextWallpaper = "Siguiente fondo";
		actPrevWallpaper = "Fondo anterior";
		actWallpaper = "Fondo · %1";
		actDnd = "No molestar";
		actNight = "Luz nocturna";
		actTerminal = "Terminal";
		hintOn = "activado";
		hintOff = "desactivado";
		hintWallpaper = "fondo";
		hintSession = "sesión";
		hintSystem = "sistema";

		# control panel
		panel = "ajustes";
		offline = "sin red";
		tileWifi = "wi-fi";
		tileBluetooth = "bluetooth";
		tileOutput = "salida";
		tileMic = "micro";
		tileDnd = "no molestar";
		tileNight = "noche";
		networks = "redes";
		scanning = "buscando";
		devices = "dispositivos";
		newDevice = "nuevo";
		noDevices = "sin dispositivos";
		audioOutput = "salida de audio";
		notifications = "avisos · %1";
		clear = "limpiar";
		dndOn = "no molestar activo";
		nothingNew = "nada nuevo";
		confirmAgain = "otra vez para confirmar";
		connectFailed = "No se ha podido conectar";
		connectedTo = "Conectado a %1";
		enterpriseHint = "%1 usa WPA-Enterprise (p. ej. eduroam): créala en la configuración avanzada";

		# dashboard, widgets, notifications
		battery = "batería %1%";
		charging = "cargando";
		network = "red · %1";
		noConnection = "sin conexión";
		media = "multimedia";
		nothingPlaying = "Nada sonando";
		notice = "aviso";

		# terminal messages of the engineering wrappers (home/engineering.nix)
		cliMissing = "%1 no está instalado en %2";
		cliNotFound = "No encuentro %1 dentro de %2";
		cliUsage = "Uso: %1 <carpeta del instalador descomprimido>";
	};

	en =
	{
		locale = "en_GB";
		dateLong = "dddd d MMMM";
		dateShort = "d MMMM";
		dayName = "dddd";
		lockDate = "%a · %d %b";
		lockLocale = "C.UTF-8";

		password = "PASSWORD";
		authFailed = "FAILED · $ATTEMPTS";
		fingerprintReady = "TOUCH THE SENSOR";
		fingerprintPresent = "READING FINGERPRINT";
		welcome = "Welcome";

		search = "SEARCH";
		appsCount = "%1 apps";
		actions = "actions";
		calculator = "calculator";
		typeExpression = "type an expression";
		enterAgain = "enter again";
		hintApps = "enter opens · > actions · = calculate · esc closes";
		hintCalc = "enter copies the result · esc closes";
		actLock = "Lock";
		actSuspend = "Suspend";
		actReboot = "Restart";
		actPowerOff = "Power off";
		actLogout = "Log out";
		actNextWallpaper = "Next wallpaper";
		actPrevWallpaper = "Previous wallpaper";
		actWallpaper = "Wallpaper · %1";
		actDnd = "Do not disturb";
		actNight = "Night light";
		actTerminal = "Terminal";
		hintOn = "on";
		hintOff = "off";
		hintWallpaper = "wallpaper";
		hintSession = "session";
		hintSystem = "system";

		panel = "settings";
		offline = "offline";
		tileWifi = "wi-fi";
		tileBluetooth = "bluetooth";
		tileOutput = "output";
		tileMic = "mic";
		tileDnd = "silent";
		tileNight = "night";
		networks = "networks";
		scanning = "scanning";
		devices = "devices";
		newDevice = "new";
		noDevices = "no devices";
		audioOutput = "audio output";
		notifications = "notifications · %1";
		clear = "clear";
		dndOn = "do not disturb is on";
		nothingNew = "nothing new";
		confirmAgain = "again to confirm";
		connectFailed = "Could not connect";
		connectedTo = "Connected to %1";
		enterpriseHint = "%1 uses WPA-Enterprise (e.g. eduroam): set it up in the advanced settings";

		battery = "battery %1%";
		charging = "charging";
		network = "network · %1";
		noConnection = "no connection";
		media = "media";
		nothingPlaying = "Nothing playing";
		notice = "notice";

		cliMissing = "%1 is not installed in %2";
		cliNotFound = "Cannot find %1 in %2";
		cliUsage = "Usage: %1 <unpacked installer folder>";
	};
}
