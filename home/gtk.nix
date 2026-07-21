# gtk.nix by poligle

{ config, pkgs, ... }:

{
    gtk = {
        enable = true;

        # GTK Theme Configuration
        theme = {
            name = "Colloid-Dark";
            package = pkgs.colloid-gtk-theme;
        };

        # Icons Configuration
        iconTheme = {
            name = "Colloid-Dark";
            package = pkgs.colloid-icon-theme;
        };

        # Cursor Configuration
        cursorTheme = {
            name = "Bibata-Modern-Classic";
            size = 20;
            package = pkgs.bibata-cursors;
        };

        # Typography Configuration
        font = {
            name = "Noto Sans CJK KR Bold";
            size = 11;
        };

        # Extra Configuration for GTK 3
        gtk3.extraConfig = {
            gtk-toolbar-style = "GTK_TOOLBAR_ICONS";
            gtk-toolbar-icon-size = "GTK_ICON_SIZE_LARGE_TOOLBAR";
            gtk-button-images = 0;
            gtk-menu-images = 0;
            gtk-enable-event-sounds = 1;
            gtk-enable-input-feedback-sounds = 0;
            gtk-xft-antialias = 1;
            gtk-xft-hinting = 1;
            gtk-xft-hintstyle = "hintslight";
            gtk-xft-rgba = "rgb";
            gtk-application-prefer-dark-theme = 1;
        };

        # Extra Configuration for GTK 4
        gtk4.extraConfig = {
            gtk-toolbar-style = "GTK_TOOLBAR_ICONS";
            gtk-toolbar-icon-size = "GTK_ICON_SIZE_LARGE_TOOLBAR";
            gtk-button-images = 0;
            gtk-menu-images = 0;
            gtk-enable-event-sounds = 1;
            gtk-enable-input-feedback-sounds = 0;
            gtk-xft-antialias = 1;
            gtk-xft-hinting = 1;
            gtk-xft-hintstyle = "hintslight";
            gtk-xft-rgba = "rgb";
            gtk-application-prefer-dark-theme = 1;
        };
    };

    # Global environment variables to force GTK4 apps to respect the theme
    home.sessionVariables = {
        GTK_THEME = "Colloid-Dark";
    };

    # Extra font package required to render your specified CJK Korean font
    home.packages = [
        pkgs.noto-fonts-cjk-sans
    ];
}
