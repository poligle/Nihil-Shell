# wallpapers.nix by poligle
#
# Renders every picture in the folders it is given (NIHIL's ../wallpapers and
# the machine's own, nihil.extraWallpapers) as a NIHIL dot matrix, once per
# output at its native size:  $out/<wallpaper>/<output>.png
# A wallpaper's name is its file's without the extension, made of letters,
# digits, "_" and "-": "Captura de pantalla 2026-11-05.PNG" is
# Captura-de-pantalla-2026-11-05, and an accent is its plain letter. The list
# of names is exposed as `passthru.names` so modules can use it without
# importing from the derivation.

{ pkgs, lib, outputs, dirs }:
let
	python = pkgs.python3.withPackages (ps: [ ps.numpy ps.pillow ]);

	# Pictures by their extension, in any case (a phone's IMG_0001.JPG too).
	# Hidden files are left out: a Mac leaves ._IMG_0001.JPG next to each
	# picture it copies, and they are not pictures.
	extensions = [ "png" "jpg" "jpeg" "gif" "webp" ];
	parts = file: builtins.match "(.+)\\.([^.]+)" file;
	extension = file: lib.toLower (lib.last (parts file));
	isImage = file: type: type == "regular" && !lib.hasPrefix "." file && parts file != null
		&& lib.elem (extension file) extensions;

	# A space or an accent can't be in a store path, and would stop the
	# whole build: the name keeps letters, digits and "_", and anything else
	# between them becomes one "-".
	accents =
	{
		"á" = "a"; "à" = "a"; "â" = "a"; "ä" = "a"; "ã" = "a"; "å" = "a";
		"é" = "e"; "è" = "e"; "ê" = "e"; "ë" = "e";
		"í" = "i"; "ì" = "i"; "î" = "i"; "ï" = "i";
		"ó" = "o"; "ò" = "o"; "ô" = "o"; "ö" = "o"; "õ" = "o";
		"ú" = "u"; "ù" = "u"; "û" = "u"; "ü" = "u";
		"ñ" = "n"; "ç" = "c"; "ý" = "y"; "ÿ" = "y";
		"Á" = "A"; "À" = "A"; "Â" = "A"; "Ä" = "A"; "Ã" = "A"; "Å" = "A";
		"É" = "E"; "È" = "E"; "Ê" = "E"; "Ë" = "E";
		"Í" = "I"; "Ì" = "I"; "Î" = "I"; "Ï" = "I";
		"Ó" = "O"; "Ò" = "O"; "Ô" = "O"; "Ö" = "O"; "Õ" = "O";
		"Ú" = "U"; "Ù" = "U"; "Û" = "U"; "Ü" = "U";
		"Ñ" = "N"; "Ç" = "C"; "Ý" = "Y";
	};
	plain = builtins.replaceStrings (builtins.attrNames accents) (builtins.attrValues accents);
	nameOf = file:
		let
			name = lib.concatStringsSep "-" (builtins.filter (part: builtins.isString part && part != "")
				(builtins.split "[^A-Za-z0-9_]+" (plain (lib.head (parts file)))));
		in
		if name != "" then name else "wallpaper";

	# Every picture by name; with the same name in two folders, the later one.
	# Each goes to the store under its clean name.
	pictures = lib.foldl' (found: dir: found // lib.mapAttrs' (file: _: lib.nameValuePair (nameOf file) (builtins.path
	{
		path = dir + "/${file}";
		name = "${nameOf file}.${extension file}";
	}))
		(lib.filterAttrs isImage (builtins.readDir dir))) { } dirs;

	outputArgs = lib.concatStringsSep " " (lib.mapAttrsToList
		(name: output: "--output ${name}:${toString output.width}x${toString output.height}:${toString output.pitch}")
		outputs);

	renderOne = name: picture: ''
		echo "nihil: rendering ${name}"
		python3 ${./dotmatrix.py} ${picture} "$out/${name}" ${outputArgs}
	'';
in
pkgs.runCommand "nihil-wallpapers"
{
	nativeBuildInputs = [ python ];
	passthru.names = builtins.attrNames pictures;
}
''
	mkdir -p $out
	${lib.concatStrings (lib.mapAttrsToList renderOne pictures)}
''
