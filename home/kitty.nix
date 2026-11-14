# kitty.nix by poligle

{ config, pkgs, lib, ... }:
{
	programs.kitty = 
	{
		enable = true;

		settings = 
		{
			confirm_os_window_close = 0;
			window_padding_width = 12;
			cursor_shape = "block";
			cursor_blink_interval = 0;
			tab_bar_style = "fade";
			tab_fade = 1;
			active_tab_font_style = "bold";
			inactive_tab_font_style = "bold";
		};

		keybindings =
		{
			"shift+insert" = "paste_from_clipboard";
			"ctrl+insert" = "copy_to_clipboard";
		};
	};
}