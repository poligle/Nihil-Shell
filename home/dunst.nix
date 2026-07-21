# dunst.nix by poligle
{ config, pkgs, lib, ... }: 
{
  services.dunst = {
    enable = true;

    package = pkgs.dunst;

    settings = {
      global = {
        # Progress bar
        progress_bar = true;
        progress_bar_height = 12;
        progress_bar_frame_width = 0;
        progress_bar_min_width = 200;
        progress_bar_max_width = 280;
        progress_bar_corner_radius = 6;
        highlight = "#e8e8ff";
        # Positioning and geometry
        follow = "mouse";
        indicate_hidden = true;
        offset = "10x10";
        # Separators and borders
        separator_height = 1;
        padding = 12;
        horizontal_padding = 14;
        frame_width = 0;
        separator_color = "#2c2c2c22";
        # Text and typography
        font = "JetBrainsMono Nerd Font 10";
        line_height = 0;
        markup = "full";
        alignment = "left";
        vertical_alignment = "center";
        word_wrap = true;
        stack_duplicates = true;
        # Visual style
        corner_radius = 10;
        timeout = 5;
        # Native icon configuration for NixOS
        min_icon_size = 16;
        max_icon_size = 32;
        text_icon_padding = 6;
        icon_theme = "Colloid-Dark";

        icon_path = let 
          iconDir = "${pkgs.colloid-icon-theme}/share/icons/Colloid-Dark";
        in lib.mkForce "${iconDir}/status/16:${iconDir}/status/24:${iconDir}/apps/scalable:${iconDir}/apps/22:${iconDir}/devices/16:${iconDir}/devices/24:${iconDir}/actions/16:${iconDir}/actions/24";
      };
      urgency_low = {
        background = "#2c2c2ccc";
        foreground = "#e6edf3";
        highlight = "#e8e8ff";
      };
      urgency_normal = {
        background = "#2c2c2ccc";
        foreground = "#e6edf3";
        highlight = "#bebeef";
      };
      urgency_critical = {
        background = "#2c2c2ccc";
        foreground = "#ffffff";
        highlight = "#cf4e4e";
      };
    };
  };
}
