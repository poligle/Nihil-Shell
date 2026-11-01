# gtk.nix by poligle

{ config, pkgs, lib, ... }:
let
    colors = config.lib.stylix.colors.withHashtag;
in
{
    gtk =
    {
        enable = true; 

        # Stylix picks adw-gtk3, the light variant, and recolours it with the
        # NIHIL palette. Some rules of the light variant keep their own dark
        # text, like the buttons of message dialogs (Thunar's "delete?"):
        # black on the dark dialog. The dark variant has light text there.
        theme.name = lib.mkForce "adw-gtk3-dark";

        # Icon Configuration: Colloid in its grey variant, so folders and
        # symbolic icons follow the NIHIL monochrome (the shell also shows
        # app icons desaturated).
        iconTheme =
        {
            name = "Colloid-Grey-Dark";
            package = pkgs.colloid-icon-theme.override { colorVariants = [ "grey" ]; };
        };

        # Extra config for GTK 3
        gtk3.extraConfig = 
        {
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

        # Extra config for GTK 4
        gtk4.extraConfig = 
        {
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

    # Red carries ink, as in the shell, never black.
    stylix.targets.gtk.extraCss = ''
        @define-color destructive_fg_color ${colors.base06};
        @define-color error_fg_color ${colors.base06};
    '';

    # Extra font package for CJK
    home.packages = 
    [
        pkgs.noto-fonts-cjk-sans
    ];
}