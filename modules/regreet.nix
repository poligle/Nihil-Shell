# regreet.nix by poligle

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
            appearance.greeting_msg = "${config.nihil.strings.welcome}, Pol";

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

    environment.sessionVariables.XKB_DEFAULT_LAYOUT = config.services.xserver.xkb.layout;
}
