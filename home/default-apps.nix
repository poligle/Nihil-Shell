# default-apps.nix by poligle
#
# What opens what: a link in Zen (home/zen.nix), a folder in Thunar, and
# text in Neovim, in kitty. xdg-open asks here, and through it Qt (the
# links and paths Nilo opens), Electron and the rest; Thunar and the other
# GTK apps read the same list (mimeapps.list). Outside a desktop
# environment Qt opens a file or a link only through xdg-open
# (qdesktopunixservices.cpp), and NIHIL had none: nothing opened.

{ config, lib, pkgs, ... }:
let
	profile = "${config.home.profileDirectory}/bin";

	# Plain text and code, which Neovim takes.
	text =
	[
		"text/plain"
		"text/markdown"
		"text/x-markdown"
		"text/x-log"
		"text/x-nix"
		"text/x-python"
		"text/x-lua"
		"text/x-csrc"
		"text/x-chdr"
		"text/x-c++src"
		"text/x-c++hdr"
		"text/x-java"
		"text/rust"
		"text/x-go"
		"text/css"
		"text/javascript"
		"application/javascript"
		"application/toml"
		"application/yaml"
		"application/x-yaml"
		"text/x-shellscript"
		"application/x-shellscript"
		"text/x-patch"
		"text/x-diff"
	];
in
{
	home.packages = [ pkgs.xdg-utils ];

	# Neovim in kitty, as "Open with" names it. NoDisplay: the launcher has
	# kitty, and Neovim's own entry is hidden (home/desktop-entries.nix).
	xdg.desktopEntries.nihil-editor =
	{
		name = "Neovim";
		genericName = "Text editor";
		exec = "${profile}/kitty -e ${profile}/nvim %F";
		terminal = false;
		noDisplay = true;
		mimeType = text;
	};

	xdg.mimeApps =
	{
		enable = true;
		# Over Zen's own claim on text/plain (home/zen.nix), which is mkDefault.
		defaultApplications = lib.genAttrs text (_: "nihil-editor.desktop")
			// { "inode/directory" = "thunar.desktop"; };
	};
}
