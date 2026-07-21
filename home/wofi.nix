# wofi.nix by poligle
{ config, pkgs, ... }:

{
  programs.wofi = {
    enable = true;

    # Core and behavioral configuration
    settings = {
      # Interface and general options
      show = "drun";
      prompt = "...";
      layer = "top";
      term = "foot";
      normal_window = true;
      width = 700;
      height = 250;

      # Layout structure
      columns = 6;
      orientation = "vertical";
      halign = "fill";
      line_wrap = "off";
      dynamic_lines = false;

      # Image and icon options
      allow_images = true;
      image_size = 56;

      # UI adjustments and behaviors
      hide_scroll = true;
      no_actions = true;
      gtk_dark = true;
      sort_order = "alphabetical";
      filter_rate = 100;

      # Keyboard shortcuts
      key_expand = "Tab";
      key_exit = "Escape";
    };

    # Custom CSS theme configuration
    style = ''
      #window {
          background-color: #2c2c2c;
          border: 20px transparent;
          border-radius: 0px;
      }

      #outer-box {
          padding: 10px;
      }

      #input {
          background-color: #464646;
          padding: 4px 8px;
      }

      #inner-box {
          margin: 10px;
      }

      #img {
          margin: 20px;
      }

      #text {
          display: none;
          font-size: 0px;
          color: transparent;
          padding: 0;
          margin: 0;
      }

      #entry {
          padding: 5px;
          border-radius: 10px;
          min-width: 72px;
          min-height: 72px;
      }

      #entry:selected {
          background-color: #2c2c2c;
          border-radius: 10px;
      }
    '';
  };
}

