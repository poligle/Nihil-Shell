# session-env.nix by poligle
#
# Environment for the apps of the session. Hyprland sets it for the apps it
# starts (home/hyprland.nix) and the NIHIL shell service for the apps opened
# from the launcher (home/shell.nix), so both get the same.

{
	QT_QPA_PLATFORM = "wayland";
	QT_QPA_PLATFORMTHEME = "qt6ct";
	QT_STYLE_OVERRIDE = "Fusion";
	# Java GUIs (MATLAB) draw blank windows on tiling compositors without it
	_JAVA_AWT_WM_NONREPARENTING = "1";
}
