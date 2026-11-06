# kitty.nix by poligle

{ config, pkgs, lib, ... }:
{
	programs.kitty = 
	{
		enable = true;

		settings = 
		{
			# Window behavior
			confirm_os_window_close = 0;
			window_padding_width = 12;
			# NIHIL: a steady block cursor, like a lit LED
			cursor_shape = "block";
			cursor_blink_interval = 0;
			# Tab bar
			tab_bar_style = "fade";
			tab_fade = 1;
			active_tab_font_style = "bold";
			inactive_tab_font_style = "bold";
		};

		# SHIFT + Insert pastes the clipboard and CTRL + Insert copies to it, as
		# everywhere else: they are what SUPER + V and SUPER + C send
		# (home/clipboard.nix, home/hyprland.nix). kitty's own SHIFT + Insert
		# pastes the primary selection, which the middle button still does.
		keybindings =
		{
			"shift+insert" = "paste_from_clipboard";
			"ctrl+insert" = "copy_to_clipboard";
		};
	};
}