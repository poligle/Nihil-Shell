# gtk.nix by poligle

{ config, pkgs, ... }:
{
    gtk = {
        enable = true; 

        # Icons Configuration
        iconTheme = {
            name = "Colloid-Dark";
            package = pkgs.colloid-icon-theme;
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
        };
    };
    # Extra font package for CJK glyph coverage
    home.packages = [
        pkgs.noto-fonts-cjk-sans
    ];
}
