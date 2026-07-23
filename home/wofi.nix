# wofi.nix by poligle

{ config, pkgs, ... }:
{
    stylix.targets.wofi.enable = false;
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
            #gtk_dark = true;
            sort_order = "alphabetical";
            filter_rate = 100;
            # Keyboard shortcuts
            key_expand = "Tab";
            key_exit = "Escape";
        };
        # Custom CSS theme configuration
        style = ''
            #window {
                background-color: ${config.lib.stylix.colors.withHashtag.base00};
                border: 20px transparent;
                border-radius: 0px;
            }
            #outer-box {
                padding: 10px;
            }
            #input {
                background-color: ${config.lib.stylix.colors.withHashtag.base01};
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
                background-color: ${config.lib.stylix.colors.withHashtag.base02};
                border-radius: 10px;
            }
        '';
    };
}
