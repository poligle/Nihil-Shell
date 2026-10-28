# wallpapers.nix by poligle
#
# Renders every image in ../wallpapers as a NIHIL dot matrix, once per output
# at its native size:  $out/<wallpaper>/<output>.png
# The list of names is exposed as `passthru.names` so modules can use it
# without importing from the derivation.

{ pkgs, lib, outputs }:
let
	python = pkgs.python3.withPackages (ps: [ ps.numpy ps.pillow ]);

	isImage = name: type: type == "regular" && builtins.match ".*\\.(png|jpg|jpeg)" name != null;
	sources = lib.filterAttrs isImage (builtins.readDir ../wallpapers);
	stem = file: lib.head (builtins.match "(.*)\\.[^.]+" file);

	outputArgs = lib.concatStringsSep " " (lib.mapAttrsToList
		(name: output: "--output ${name}:${toString output.width}x${toString output.height}:${toString output.pitch}")
		outputs);

	renderOne = file: ''
		echo "nihil: rendering ${file}"
		python3 ${./dotmatrix.py} ${../wallpapers + "/${file}"} "$out/${stem file}" ${outputArgs}
	'';
in
pkgs.runCommand "nihil-wallpapers"
{
	nativeBuildInputs = [ python ];
	passthru.names = map stem (builtins.attrNames sources);
}
''
	mkdir -p $out
	${lib.concatMapStrings renderOne (builtins.attrNames sources)}
''
