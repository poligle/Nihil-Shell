# viewers.nix by poligle

{ config, osConfig, pkgs, lib, ... }:
let
	p = osConfig.nihil.tokens.palette;
	f = osConfig.nihil.tokens.fonts;

	bare = package: pkgs.symlinkJoin
	{
		name = "${package.name}-bare";
		paths = [ package ];
		postBuild = "rm -rf $out/share/applications";
	};

	imv = bare pkgs.imv;
	mpv = bare pkgs.mpv;
	zathura = bare pkgs.zathura;

	pictures =
	[
		"image/png"
		"image/jpeg"
		"image/gif"
		"image/webp"
		"image/avif"
		"image/heic"
		"image/heif"
		"image/jxl"
		"image/bmp"
		"image/tiff"
		"image/svg+xml"
	];

	videos =
	[
		"video/mp4"
		"video/webm"
		"video/x-matroska"
		"video/quicktime"
		"video/x-msvideo"
		"video/mpeg"
		"video/ogg"
		"video/3gpp"
		"video/mp2t"
		"video/x-flv"
		"video/x-ms-wmv"
		"audio/mpeg"
		"audio/flac"
		"audio/x-flac"
		"audio/ogg"
		"audio/x-vorbis+ogg"
		"audio/opus"
		"audio/x-opus+ogg"
		"audio/wav"
		"audio/x-wav"
		"audio/mp4"
		"audio/x-m4a"
		"audio/aac"
	];

	documents =
	[
		"application/pdf"
		"application/epub+zip"
		"application/oxps"
		"application/vnd.ms-xpsdocument"
		"application/postscript"
		"image/vnd.djvu"
		"application/vnd.comicbook+zip"
		"application/x-cbz"
	];

	viewer = pkgs.writeShellScript "nihil-viewer" ''
		if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
			exec ${imv}/bin/imv -- "$@"
		fi
		shopt -s nullglob
		file="$(${pkgs.coreutils}/bin/realpath -s -- "$1")"
		folder="$(${pkgs.coreutils}/bin/dirname -- "$file")"
		all=()
		for each in "$folder"/*; do
			case "''${each,,}" in
				*.png | *.jpg | *.jpeg | *.jfif | *.gif | *.webp | *.avif | *.heic | *.heif | *.jxl | *.bmp | *.tif | *.tiff | *.svg | *.qoi)
					all+=( "$each" ) ;;
			esac
		done
		for each in "''${all[@]}"; do
			if [ "$each" = "$file" ]; then
				exec ${imv}/bin/imv -n "$file" -- "''${all[@]}"
			fi
		done
		exec ${imv}/bin/imv -- "$file"
	'';
in
{
	home.packages = [ imv mpv zathura ];

	xdg.configFile."imv/config".text = ''
		[options]
		background = ${p.void}
		overlay_font = ${f.mono}:11
		overlay_text_color = ${p.dim}
		overlay_background_color = ${p.void}
		overlay_background_alpha = cc
		overlay_position_bottom = true
	'';

	xdg.configFile."mpv/mpv.conf".text = ''
		osd-font="${f.sans}"
		osd-color="#${p.ink}"
		keep-open=yes
		hwdec=auto-safe
	'';

	xdg.configFile."zathura/zathurarc".text = ''
		set font "${f.mono} 10"
		set default-bg "#${p.void}"
		set default-fg "#${p.ink}"
		set statusbar-bg "#${p.void}"
		set statusbar-fg "#${p.dim}"
		set inputbar-bg "#${p.void}"
		set inputbar-fg "#${p.ink}"
		set notification-bg "#${p.surface}"
		set notification-fg "#${p.ink}"
		set notification-warning-bg "#${p.surface}"
		set notification-warning-fg "#${p.ink}"
		set notification-error-bg "#${p.signal}"
		set notification-error-fg "#${p.ink}"
		set completion-bg "#${p.surface}"
		set completion-fg "#${p.dim}"
		set completion-group-bg "#${p.void}"
		set completion-group-fg "#${p.muted}"
		set completion-highlight-bg "#${p.raised}"
		set completion-highlight-fg "#${p.ink}"
		set index-bg "#${p.void}"
		set index-fg "#${p.dim}"
		set index-active-bg "#${p.raised}"
		set index-active-fg "#${p.ink}"
		set highlight-color "rgba(242, 242, 242, 0.25)"
		set highlight-active-color "rgba(242, 242, 242, 0.5)"
		set render-loading-bg "#${p.void}"
		set render-loading-fg "#${p.muted}"
		set recolor-lightcolor "#${p.void}"
		set recolor-darkcolor "#${p.ink}"
		set selection-clipboard clipboard
		set window-title-basename true
	'';

	xdg.desktopEntries =
	{
		nihil-viewer =
		{
			name = "imv";
			genericName = "Image viewer";
			exec = "${viewer} %F";
			terminal = false;
			noDisplay = true;
			mimeType = pictures;
		};

		nihil-player =
		{
			name = "mpv";
			genericName = "Video player";
			exec = "${mpv}/bin/mpv --player-operation-mode=pseudo-gui -- %U";
			terminal = false;
			noDisplay = true;
			mimeType = videos;
		};

		nihil-reader =
		{
			name = "Zathura";
			genericName = "Document viewer";
			exec = "${zathura}/bin/zathura %F";
			terminal = false;
			noDisplay = true;
			mimeType = documents;
		};
	};

	xdg.mimeApps.defaultApplications =
		lib.genAttrs pictures (_: "nihil-viewer.desktop")
		// lib.genAttrs videos (_: "nihil-player.desktop")
		// lib.genAttrs documents (_: "nihil-reader.desktop");
}
