# kitty.nix by poligle

{ config, pkgs, lib, ... }:
{
	programs.kitty = {
		enable = true;

		settings = {
			# Window behavior
			confirm_os_window_close = 0;
			# Tab bar
			tab_bar_style = "fade";
			tab_fade = 1;
			active_tab_font_style = "bold";
			inactive_tab_font_style = "bold";
		};
	};
}
