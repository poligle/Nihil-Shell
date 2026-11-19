# zen.nix by poligle

{ config, lib, pkgs, inputs, ... }:
let
    colors = config.lib.stylix.colors.withHashtag;
in
{
    imports = [ inputs.zen-browser.homeModules.beta ];

    programs.zen-browser =
    {
        enable = true;
        setAsDefaultBrowser = true;
        profiles =
        {
            default =
            {
                settings =
                {
                    "ui.highlight" = colors.base03;
                    "ui.highlighttext" = colors.base06;
                };

                # Stylix's theme leaves the find bar (Ctrl + F) in Zen's light colours.
                userChrome = ''
                    findbar
                    {
                        background-color: ${colors.base00} !important;
                        color: ${colors.base05} !important;
                        border-color: ${colors.base02} !important;
                        box-shadow: none !important;
                    }

                    findbar .findbar-textbox
                    {
                        background-color: ${colors.base01} !important;
                        color: ${colors.base06} !important;
                        border: 1px solid ${colors.base02} !important;
                        border-radius: 8px !important;
                        outline: none !important;
                        box-shadow: none !important;
                    }

                    findbar .findbar-textbox:focus { border-color: ${colors.base03} !important; }
                    findbar .findbar-textbox[status="notfound"] { border-color: ${colors.base08} !important; }
                    findbar .findbar-textbox::placeholder { color: ${colors.base04} !important; }

                    findbar :is(label, description, .findbar-label, .found-matches, .findbar-find-status)
                    {
                        color: ${colors.base04} !important;
                    }

                    findbar :is(toolbarbutton, checkbox)
                    {
                        color: ${colors.base05} !important;
                        fill: ${colors.base05} !important;
                        background-color: transparent !important;
                    }

                    findbar :is(toolbarbutton, checkbox):hover { background-color: ${colors.base02} !important; }

                    findbar checkbox .checkbox-check
                    {
                        background-color: ${colors.base01} !important;
                        border: 1px solid ${colors.base03} !important;
                    }

                    findbar checkbox[checked] .checkbox-check
                    {
                        background-color: ${colors.base06} !important;
                        fill: ${colors.base00} !important;
                    }
                '';
            };
        };
    };

    stylix.targets.zen-browser.profileNames = [ "default" ];
}
