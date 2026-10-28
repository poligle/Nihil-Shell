# zsh.nix by poligle

{ config, osConfig, pkgs, ... }:
let
    p = osConfig.nihil.tokens.palette;
in
{
    programs.zsh = 
    {
        enable = true;
        enableCompletion = true;

        oh-my-zsh = 
        {
            enable = true;
            theme = ""; 
            plugins = 
            [
                "git"
                "sudo"
            ];
        };

        plugins = 
        [
            {
                name = "zsh-autosuggestions";
                src = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions";
            }
            {
                name = "zsh-syntax-highlighting";
                src = "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting";
            }
        ];

        shellAliases = 
        {
            trash = "trash-put";
            ".." = "cd ..";
            "..." = "cd ../..";
            ll = "ls -lah";
            la = "ls -A";

            # NixOS
            nrebuild = "sudo nixos-rebuild switch --flake ~/nixos-config#thinkpad";
            nupdate = "cd ~/nixos-config && nix flake update && sudo nixos-rebuild switch --flake ~/nixos-config#thinkpad";
            ncheck = "cd ~/nixos-config && nix flake check";
            ngc = "sudo nix-collect-garbage --delete-older-than 7d";
            
            gs = "git status";
            ga = "git add .";
            gc = "git commit -m";
            gp = "git push";
            gl = "git log --oneline -10";
            gd = "git diff";
        };
    };

    # NIHIL prompt: monochrome, declarative (replaces powerlevel10k and the
    # untracked ~/.p10k.zsh). Red only when the last command failed.
    programs.starship =
    {
        enable = true;
        enableZshIntegration = true;
        settings =
        {
            add_newline = true;
            format = "$directory$git_branch$git_status$nix_shell$cmd_duration$line_break$character";

            character =
            {
                success_symbol = "[›](bold #${p.ink})";
                error_symbol = "[›](bold #${p.signal})";
            };
            directory =
            {
                style = "bold #${p.ink}";
                truncation_length = 3;
                truncate_to_repo = true;
                format = "[$path]($style)[$read_only]($read_only_style) ";
            };
            git_branch =
            {
                style = "#${p.dim}";
                symbol = "";
                format = "[· $branch]($style) ";
            };
            git_status =
            {
                style = "#${p.muted}";
                format = "([$all_status$ahead_behind]($style) )";
            };
            nix_shell =
            {
                style = "#${p.dim}";
                format = "[· nix $state]($style) ";
            };
            cmd_duration =
            {
                style = "#${p.muted}";
                min_time = 2000;
                format = "[· $duration]($style) ";
            };
        };
    };
}
