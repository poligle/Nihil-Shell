# shaders.nix by poligle
#
# The smoked glass's shaders (home/shell/shaders/), compiled for Qt's RHI:
# SPIR-V for Vulkan and GLSL for OpenGL 3.2 and up (and GLES 3). The shell
# (home/shell.nix) and the greeter (modules/greeter.nix) both carry them.

{ pkgs }:
pkgs.runCommand "nihil-glass-shaders" { } ''
	qsb=$(find -L ${pkgs.qt6.qtshadertools} -name qsb -type f | head -n 1)
	[ -n "$qsb" ] || { echo "qsb not found in qtshadertools" >&2; exit 1; }
	mkdir -p $out
	for shader in ${../home/shell/shaders}/*.vert ${../home/shell/shaders}/*.frag; do
		"$qsb" --glsl "300 es,150" -o "$out/$(basename "$shader").qsb" "$shader"
	done
''
