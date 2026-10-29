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
		hintAppsNilo = "enter abre · > acciones · = calcular · ? nilo · esc cierra";
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
		# Nilo, the assistant (modules/nilo.nix, home/shell/nilo)
		nilo = "nilo";
		niloAsk = "pregúntame lo que quieras";
		niloHint = "enter pregunta · ctrl+n nueva conversación · esc cierra";
		niloHintBusy = "esc para la respuesta";
		niloHintOff = "borra el ? para volver · esc cierra";
		niloHintConfirm = "enter dos veces confirma · esc cancela";
		niloHintIntro = "enter sigue · ↑↓ elige · espacio marca · esc cierra";
		niloHintSettings = "↑↓ elige · espacio marca · esc vuelve";
		niloHintAuthorize = "espacio o enter autoriza · esc cancela";
		niloOff = "Nilo está apagado";
		niloOffHow = "Actívalo con nihil.nilo.enable = true en tu host y haz rebuild.";
		niloAsleep = "dormido";
		niloWaking = "despertando";
		niloAwake = "despierto · %1 GB";
		niloThinking = "pensando";
		niloWriting = "escribiendo";
		niloWorking = "trabajando";
		niloWaitingYou = "esperándote";
		niloNoOllama = "sin ollama";
		niloOllamaStartingShort = "arrancando ollama";
		niloOllamaDown = "Ollama no está en marcha.";
		niloOllamaStarting = "Arrancando Ollama…";
		niloStartOllama = "arrancar ollama";
		niloOllamaHelp = "más en: journalctl -u ollama -b";
		niloDownloading = "descargando · %1%";
		niloDownloadingModel = "Descargando %1 · %2%";
		niloEmpty = "Pregúntame algo. Si hace falta, busco en internet.";
		niloEmptyOffline = "Pregúntame algo.";
		niloTryFlake = "¿Qué es un flake de Nix?";
		niloTryNews = "¿Qué hay de nuevo en NixOS?";
		niloTryDisk = "¿Cuánto disco me queda?";
		niloTryFiles = "¿Qué hay en mi repositorio?";
		niloTryPush = "Sube los cambios de mi config";
		niloCopy = "copiar";
		niloCopied = "copiado";
		niloStopped = "parado";
		niloRate = "%1 tok/s";

		toolSearching = "buscando «%1»";
		toolSearched = "%1 resultados de «%2»";
		toolReading = "leyendo %1";
		toolRead = "leído · %1";
		toolSystem = "mirando este ordenador";
		toolSystemDone = "visto este ordenador";
		toolGitStatus = "mirando el repositorio";
		toolGitStatusDone = "%1 cambios en %2";
		toolGitCommit = "preparando el commit";
		toolGitCommitted = "commit %1";
		toolGitPushed = "commit %1 · subido";
		toolGitPushedOnly = "subido";
		toolDeclined = "cancelado";
		toolFailed = "falló · %1";
		toolListing = "mirando los archivos";
		toolListed = "%1 archivos";
		toolOpening = "abriendo %1";
		toolOpened = "leído %1 · %2 líneas";
		toolChanging = "preparando %1";
		toolChanged = "cambiado %1 · +%2 −%3";
		toolCreated = "creado %1 · %2 líneas";

		confirmCommitPush = "commit y push";
		confirmCommit = "commit";
		confirmPush = "push";
		confirmMore = "y %1 más";
		confirmAhead = "%1 commits sin subir";
		confirmFile = "archivo";
		confirmEdit = "cambiar";
		confirmCreate = "crear";
		confirmMoreLines = "y %1 líneas más";
		confirmOk = "confirmar";
		confirmCancel = "cancelar";
		confirmDone = "confirmado";
		confirmDeclined = "cancelado";
		quoted = "«%1»";

		niloErrOllama = "Ollama no está en marcha.";
		niloErrModel = "Falta el modelo %1.";
		niloErrMemory = "No hay memoria para %1: prueba uno más pequeño.";
		niloErrNoModel = "Elige un modelo en el engranaje.";
		niloErrRepo = "%1 no es un repositorio git.";
		niloErrOther = "Algo ha fallado · %1";
		niloDownload = "descargar";
		niloDelete = "borrar";

		introHello = "Hola. Soy Nilo.";
		introLocal = "Vivo en este ordenador: el modelo funciona aquí, sin cuentas ni nube. Solo salgo a internet si me dejas, para buscar.";
		introCall = "Llámame cuando quieras";
		introBind = "desde cualquier sitio";
		introCopilot = "la tecla Copilot, si tu portátil la tiene";
		introLauncher = "en el launcher, empieza por ?";
		keySpace = "ESPACIO";
		introSleep = "Si pasan %1 minutos sin preguntas, me duermo y dejo libre la memoria. Despierto en cuanto escribes.";
		introModel = "Elige mi modelo";
		introModelSub = "Tienes %1 GB de RAM. Los grandes saben más; los pequeños van más rápido.";
		introAccess = "¿Qué puedo hacer?";
		introAccessSub = "Lo cambias cuando quieras en el engranaje.";
		introDone = "Listo.";
		introDoneSub = "Pregúntame lo que quieras.";
		introNext = "seguir";
		introStart = "empezar";
		introKeepsDownloading = "sigue descargándose mientras tanto";

		modelRecommended = "recomendado";
		modelInstalled = "descargado";
		modelSelected = "en uso";
		modelSize = "%1 GB";
		modelRam = "≈ %1 GB de RAM";
		modelTight = "justo para tu RAM";
		modelFailed = "no se ha podido descargar · %1";
		modelFailedOllama = "ollama no está en marcha";

		accessWeb = "Internet";
		accessWebSub = "buscar y leer páginas";
		accessSystem = "Este ordenador";
		accessSystemSub = "memoria, disco, batería, versión de NixOS";
		accessGit = "Git";
		accessGitSub = "add, commit y push en %1, siempre preguntándote antes";
		accessGitGuard = "Podré hacer add, commit y push en %1 con tu usuario de git. Antes de cada commit o push te enseño qué voy a hacer y espero tu confirmación.";
		accessWrite = "Archivos";
		accessWriteSub = "leer, crear y cambiar archivos en %1, enseñándote cada cambio antes";
		accessWriteGuard = "Podré leer, crear y cambiar archivos dentro de %1, nunca fuera de él ni en .git. Antes de cada cambio te enseño el diff y no toco nada hasta que confirmes.";
		accessAuthorize = "autorizar";

		setModel = "modelo";
		setAccess = "acceso";
		setRepo = "repositorio";
		setRepoPath = "ruta";
		setRepoNote = "Al cambiar de repositorio, git y archivos se apagan hasta que los autorices otra vez.";
		setMemory = "memoria";
		setSleepAfter = "dormir tras";
		setMinutes = "%1 min";
		setSleepNow = "dormir ahora";
		setAwakeUntil = "despierto · %1 GB · %2% en la GPU · hasta las %3";
		setAsleep = "dormido · no ocupa memoria";
		setThink = "Pensar antes de responder";
		setThinkSub = "más lento; mejor para problemas difíciles";
		setIntro = "volver a presentarse";
		setRebuild = "Activar o quitar Nilo y elegir CPU o GPU se hace en nihil.nilo, en tu host (rebuild).";
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
		hintAppsNilo = "enter opens · > actions · = calculate · ? nilo · esc closes";
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
		nilo = "nilo";
		niloAsk = "ask me anything";
		niloHint = "enter asks · ctrl+n new conversation · esc closes";
		niloHintBusy = "esc stops the answer";
		niloHintOff = "delete the ? to go back · esc closes";
		niloHintConfirm = "enter twice confirms · esc cancels";
		niloHintIntro = "enter next · ↑↓ choose · space toggles · esc closes";
		niloHintSettings = "↑↓ choose · space toggles · esc goes back";
		niloHintAuthorize = "space or enter authorizes · esc cancels";
		niloOff = "Nilo is off";
		niloOffHow = "Turn it on with nihil.nilo.enable = true in your host and rebuild.";
		niloAsleep = "asleep";
		niloWaking = "waking up";
		niloAwake = "awake · %1 GB";
		niloThinking = "thinking";
		niloWriting = "writing";
		niloWorking = "working";
		niloWaitingYou = "waiting for you";
		niloNoOllama = "no ollama";
		niloOllamaStartingShort = "starting ollama";
		niloOllamaDown = "Ollama isn't running.";
		niloOllamaStarting = "Starting Ollama…";
		niloStartOllama = "start ollama";
		niloOllamaHelp = "more in: journalctl -u ollama -b";
		niloDownloading = "downloading · %1%";
		niloDownloadingModel = "Downloading %1 · %2%";
		niloEmpty = "Ask me something. I'll search the web if I need to.";
		niloEmptyOffline = "Ask me something.";
		niloTryFlake = "What is a Nix flake?";
		niloTryNews = "What's new in NixOS?";
		niloTryDisk = "How much disk space is left?";
		niloTryFiles = "What's in my repository?";
		niloTryPush = "Push my config changes";
		niloCopy = "copy";
		niloCopied = "copied";
		niloStopped = "stopped";
		niloRate = "%1 tok/s";

		toolSearching = "searching “%1”";
		toolSearched = "%1 results for “%2”";
		toolReading = "reading %1";
		toolRead = "read · %1";
		toolSystem = "looking at this computer";
		toolSystemDone = "looked at this computer";
		toolGitStatus = "looking at the repository";
		toolGitStatusDone = "%1 changes on %2";
		toolGitCommit = "preparing the commit";
		toolGitCommitted = "commit %1";
		toolGitPushed = "commit %1 · pushed";
		toolGitPushedOnly = "pushed";
		toolDeclined = "cancelled";
		toolFailed = "failed · %1";
		toolListing = "looking at the files";
		toolListed = "%1 files";
		toolOpening = "opening %1";
		toolOpened = "read %1 · %2 lines";
		toolChanging = "preparing %1";
		toolChanged = "changed %1 · +%2 −%3";
		toolCreated = "created %1 · %2 lines";

		confirmCommitPush = "commit and push";
		confirmCommit = "commit";
		confirmPush = "push";
		confirmMore = "and %1 more";
		confirmAhead = "%1 commits not pushed yet";
		confirmFile = "file";
		confirmEdit = "change";
		confirmCreate = "create";
		confirmMoreLines = "and %1 more lines";
		confirmOk = "confirm";
		confirmCancel = "cancel";
		confirmDone = "confirmed";
		confirmDeclined = "cancelled";
		quoted = "“%1”";

		niloErrOllama = "Ollama isn't running.";
		niloErrModel = "The model %1 isn't downloaded.";
		niloErrMemory = "Not enough memory for %1: try a smaller one.";
		niloErrNoModel = "Choose a model in the settings.";
		niloErrRepo = "%1 is not a git repository.";
		niloErrOther = "Something went wrong · %1";
		niloDownload = "download";
		niloDelete = "delete";

		introHello = "Hi. I'm Nilo.";
		introLocal = "I live on this computer: the model runs here, with no account and no cloud. I only go online if you let me, to search.";
		introCall = "Call me whenever you like";
		introBind = "from anywhere";
		introCopilot = "the Copilot key, if your laptop has one";
		introLauncher = "in the launcher, start with ?";
		keySpace = "SPACE";
		introSleep = "After %1 minutes without questions I go to sleep and free the memory. I wake up as soon as you type.";
		introModel = "Choose my model";
		introModelSub = "You have %1 GB of RAM. Bigger ones know more; smaller ones are faster.";
		introAccess = "What may I do?";
		introAccessSub = "Change it any time in the settings.";
		introDone = "Ready.";
		introDoneSub = "Ask me anything.";
		introNext = "next";
		introStart = "start";
		introKeepsDownloading = "it keeps downloading meanwhile";

		modelRecommended = "recommended";
		modelInstalled = "downloaded";
		modelSelected = "in use";
		modelSize = "%1 GB";
		modelRam = "≈ %1 GB of RAM";
		modelTight = "tight for your RAM";
		modelFailed = "download failed · %1";
		modelFailedOllama = "ollama isn't running";

		accessWeb = "Internet";
		accessWebSub = "search and read pages";
		accessSystem = "This computer";
		accessSystemSub = "memory, disk, battery, NixOS version";
		accessGit = "Git";
		accessGitSub = "add, commit and push in %1, always asking you first";
		accessGitGuard = "I'll be able to add, commit and push in %1 as your git user. Before each commit or push I show you what I'll do and wait for your confirmation.";
		accessWrite = "Files";
		accessWriteSub = "read, create and change files in %1, showing you each change first";
		accessWriteGuard = "I'll be able to read, create and change files inside %1, never outside it or in .git. Before each change I show you the diff, and nothing is touched until you confirm.";
		accessAuthorize = "authorize";

		setModel = "model";
		setAccess = "access";
		setRepo = "repository";
		setRepoPath = "path";
		setRepoNote = "Switching repositories turns git and files off until you authorize them again.";
		setMemory = "memory";
		setSleepAfter = "sleep after";
		setMinutes = "%1 min";
		setSleepNow = "sleep now";
		setAwakeUntil = "awake · %1 GB · %2% on the GPU · until %3";
		setAsleep = "asleep · takes no memory";
		setThink = "Think before answering";
		setThinkSub = "slower; better for hard problems";
		setIntro = "introduce yourself again";
		setRebuild = "Turning Nilo on or off and choosing CPU or GPU is done in nihil.nilo, in your host (rebuild).";
	};
}
