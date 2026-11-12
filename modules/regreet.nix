# regreet.nix by poligle
#
# ReGreet: what NIHIL's greeter falls back to (modules/greeter.nix), or the
# greeter itself with nihil.greeter = "regreet".

{ config, lib, pkgs, ... }:
let
    p = config.nihil.tokens.palette;
    f = config.nihil.tokens.fonts;
in
{
    programs.regreet =
    {
        enable = true;
        cageArgs = [ "-s" "-d" "-m" "last" ];

        settings =
        {
            # The wallpaper the user has now (home/wallpaper.nix keeps the link);
            # NIHIL's own until someone has logged in.
            background.path = lib.mkForce "/var/lib/nihil/greeter/wallpaper.png";
            appearance.greeting_msg = config.nihil.strings.welcome
                + lib.optionalString (config.nihil.user.greeting != "") ", ${config.nihil.user.greeting}";

            widget.clock =
            {
                format = "%H:%M";
                resolution = "500ms";
                label_width = 150;
            };
        };
    };

    # NIHIL on top of Stylix's ReGreet theme (which already sets the
    # dot-matrix wallpaper, Space Grotesk and the monochrome colours).
    # ReGreet draws the login box and the clock as `frame.background`.
    stylix.targets.regreet.extraCss = ''
        frame.background {
            background-color: alpha(#${p.void}, 0.86);
            border: 1px solid #${p.line};
            border-radius: 24px;
        }

        frame.widget-clock {
            margin-top: 56px;
            padding: 6px 22px;
        }

        frame.widget-clock label {
            font-family: "${f.dot}";
            font-weight: 800;
            font-size: 44px;
            color: #${p.ink};
        }

        entry,
        dropdown > button {
            min-height: 40px;
            border-radius: 999px;
            background-color: #${p.surface};
            border: 1px solid #${p.line};
            box-shadow: none;
        }

        entry:focus-within {
            border-color: #${p.muted};
            outline: none;
        }

        button {
            border-radius: 999px;
            padding: 6px 18px;
            font-family: "${f.mono}";
        }

        button.suggested-action {
            background-color: #${p.ink};
            color: #${p.void};
        }

        button.destructive-action {
            background-color: transparent;
            color: #${p.signal};
            border: 1px solid #${p.signal};
        }
    '';

    # cage, under both greeters, makes its keyboard from these alone: the
    # variant too (Preferences, Region), or a password with one of its
    # characters would not be typed at the login as in the session and the
    # lock screen, where Hyprland has the whole layout (home/hyprland.nix).
    # xkbcommon takes a variant from here only along with the layout, so
    # Hyprland's own stays as it is.
    environment.sessionVariables =
        let xkb = config.services.xserver.xkb; in
        { XKB_DEFAULT_LAYOUT = xkb.layout; }
        // lib.optionalAttrs (xkb.variant != "") { XKB_DEFAULT_VARIANT = xkb.variant; }
        // lib.optionalAttrs (xkb.model != "") { XKB_DEFAULT_MODEL = xkb.model; };

    systemd.tmpfiles.rules =
    [
        "d /var/lib/nihil/greeter 0755 ${config.nihil.user.name} users -"
        "L /var/lib/nihil/greeter/wallpaper.png - - - - ${config.nihil.wallpapers}/${config.nihil.wallpaper}/${config.nihil.primaryOutput}.png"
    ];
}
