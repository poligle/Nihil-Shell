# vscode.nix by poligle

{ osConfig, pkgs, ... }:
let
    foreground = "#${osConfig.nihil.tokens.base16.base05}";
in
{
    programs.vscode = 
    {
        enable = true;
        package = pkgs.vscode.fhs;

        profiles.default.extensions = with pkgs.vscode-extensions; 
        [
            ms-python.python
            ms-toolsai.jupyter
        ];

        profiles.default.userSettings = 
        {
            "python.defaultInterpreterPath" = "~/.nix-profile/bin/python";

            # NIHIL: red (base08) is reserved for errors, so variables and
            # tags use the plain foreground instead.
            "editor.tokenColorCustomizations".textMateRules =
            [
                {
                    scope = [ "variable" "variable.other" "variable.parameter" "support.variable" "entity.name.tag" "meta.definition.variable" ];
                    settings.foreground = foreground;
                }
            ];
            "editor.semanticTokenColorCustomizations".rules =
            {
                variable = foreground;
                parameter = foreground;
                property = foreground;
            };
        };
    };
}
