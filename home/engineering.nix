# engineering.nix by poligle

{ config, pkgs, lib, ... }:
let
	palette = config.lib.stylix.colors.withHashtag;
	installRoot = "${config.home.homeDirectory}/eda";
	licenseEnv = "${config.xdg.configHome}/eda/licenses.env";

	edaFhs = pkgs.buildFHSEnv
	{
		name = "eda-fhs";

		targetPkgs = pkgs: with pkgs;
		[
			bash
			coreutils
			findutils
			gnugrep
			gnused
			gawk
			which
			procps
			util-linux
			file
			unzip
			zip
			gnutar
			gzip
			bzip2
			xz
			zstd
			perl
			python3
			tcsh
			ksh
			gcc

			glibc
			glibcLocales
			zlib
			libxcrypt-legacy
			ncurses
			ncurses5
			libnsl
			libuuid
			krb5
			openssl
			expat
			libxml2
			libpng
			libjpeg
			libtiff
			freetype
			fontconfig
			dejavu_fonts
			pam
			libselinux
			libsndfile

			glib
			dbus
			nss
			nspr
			cups
			alsa-lib
			libpulseaudio
			gtk2
			gtk3
			pango
			cairo
			gdk-pixbuf
			atk
			at-spi2-atk
			at-spi2-core
			gst_all_1.gstreamer
			gst_all_1.gst-plugins-base

			libGL
			libGLU
			libglvnd
			mesa
			libdrm
			libxkbcommon
			motif

			libx11
			libxext
			libxrender
			libxtst
			libxi
			libxrandr
			libxcursor
			libxinerama
			libxcomposite
			libxdamage
			libxfixes
			libxscrnsaver
			libxmu
			libxt
			libxpm
			libxft
			libxp
			libxkbfile
			libice
			libsm
			libxcb
			libxcb-util
			libxcb-image
			libxcb-keysyms
			libxcb-render-util
			libxcb-wm
			libxcb-cursor
		];

		profile = ''
			export EDA_HOME="${installRoot}"
			export MATLAB_HOME="${installRoot}/matlab"
			export FEKO_HOME="${installRoot}/altair"
			export HPEESOF_DIR="${installRoot}/keysight/ads"
			export QT_QPA_PLATFORM=xcb
			export _JAVA_AWT_WM_NONREPARENTING=1
			unset QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE
			if [ -r "${licenseEnv}" ]; then
				. "${licenseEnv}"
			fi
		'';

		runScript = "bash";
	};

	launchInFhs = name: script: pkgs.writeShellScriptBin name ''
		exec ${edaFhs}/bin/eda-fhs ${pkgs.writeShellScript "${name}-launch" script} "$@"
	'';

	matlab = launchInFhs "matlab" ''
		if [ ! -x "$MATLAB_HOME/bin/matlab" ]; then
			echo "MATLAB no está instalado en $MATLAB_HOME" >&2
			exit 1
		fi
		exec "$MATLAB_HOME/bin/matlab" "$@"
	'';

	feko = launchInFhs "feko" ''
		tool="''${1:-cadfeko}"
		[ "$#" -gt 0 ] && shift
		binary="$(find "$FEKO_HOME" -maxdepth 7 -type f -path "*/feko/bin/$tool" 2>/dev/null | head -n1)"
		if [ -z "$binary" ]; then
			echo "No encuentro $tool dentro de $FEKO_HOME" >&2
			exit 1
		fi
		exec "$binary" "$@"
	'';

	ads = launchInFhs "ads" ''
		if [ ! -x "$HPEESOF_DIR/bin/ads" ]; then
			echo "ADS no está instalado en $HPEESOF_DIR" >&2
			exit 1
		fi
		exec "$HPEESOF_DIR/bin/ads" "$@"
	'';

	letterIcon = name: letter: color: "${pkgs.writeText "${name}.svg" ''
		<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
			<rect width="64" height="64" rx="14" fill="${palette.base01}"/>
			<text x="32" y="43" text-anchor="middle" font-family="${config.stylix.fonts.monospace.name}" font-size="30" font-weight="bold" fill="${color}">${letter}</text>
		</svg>
	''}";

	application = name: exec: letter: color:
	{
		inherit name exec;
		icon = letterIcon (lib.toLower (lib.replaceStrings [ " " ] [ "-" ] name)) letter color;
		categories = [ "Science" "Engineering" ];
		terminal = false;
	};
in
{
	home.packages =
	[
		edaFhs
		matlab
		feko
		ads
	];

	xdg.desktopEntries =
	{
		matlab = application "MATLAB" "matlab -desktop" "M" palette.base09;
		cadfeko = application "CADFEKO" "feko cadfeko" "F" palette.base0B;
		postfeko = application "POSTFEKO" "feko postfeko" "P" palette.base0C;
		ads = application "Keysight ADS" "ads" "A" palette.base0E;
	};
}
