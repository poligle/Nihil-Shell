# engineering.nix by poligle

{ config, pkgs, lib, ... }:
let
	installRoot = "${config.home.homeDirectory}/eda";
	systemLibstdcxx = "${pkgs.stdenv.cc.cc.lib}/lib/libstdc++.so.6";
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
			libxshmfence
			libxxf86vm
			libxfont_2
			xkbcomp

			stdenv.cc.cc.lib
			libgbm
			libcap
			fribidi
			libtool.lib
			numactl
			pixman
			libtirpc
			systemdLibs
			cacert
			iproute2
			net-tools
			gnumake
			wget
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
		export LD_PRELOAD="${systemLibstdcxx}"
		exec "$MATLAB_HOME/bin/matlab" "$@"
	'';

	matlab-install = launchInFhs "matlab-install" ''
		installer="''${1:-$PWD}"
		[ "$#" -gt 0 ] && shift
		if [ ! -f "$installer/install" ]; then
			echo "Uso: matlab-install <carpeta del instalador descomprimido>" >&2
			exit 1
		fi
		cd "$installer"
		export LD_PRELOAD="${systemLibstdcxx}"
		exec ./install "$@"
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

	application = name: exec: icon:
	{
		inherit name exec icon;
		categories = [ "Science" "Engineering" ];
		terminal = false;
	};
in
{
	home.packages =
	[
		edaFhs
		matlab
		matlab-install
		feko
		ads
	];

	xdg.desktopEntries =
	{
		matlab = application "MATLAB" "matlab -desktop" "matlab";
		cadfeko = application "CADFEKO" "feko cadfeko" "/home/poligle/.icons/feko.svg";
		postfeko = application "POSTFEKO" "feko postfeko" "com.github.alexhuntley.Plots";
		ads = application "Keysight ADS" "ads" "gtkwave";
	};
}