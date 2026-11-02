# wallpapers.nix by poligle
#
# Renders every image in the folders it is given (NIHIL's ../wallpapers and
# the machine's own, nihil.extraWallpapers) as a NIHIL dot matrix, once per
# output at its native size:  $out/<wallpaper>/<output>.png
# The list of names is exposed as `passthru.names` so modules can use it
# without importing from the derivation.

{ pkgs, lib, outputs, dirs }:
let
	python = pkgs.python3.withPackages (ps: [ ps.numpy ps.pillow ]);

	isImage = name: type: type == "regular" && builtins.match ".*\\.(png|jpg|jpeg)" name != null;
	stem = file: lib.head (builtins.match "(.*)\\.[^.]+" file);

	# Every picture by name; with the same name in two folders, the later one.
	pictures = lib.foldl' (found: dir: found // lib.mapAttrs' (file: _: lib.nameValuePair (stem file) (dir + "/${file}"))
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
