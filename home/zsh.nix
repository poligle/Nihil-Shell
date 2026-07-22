# zsh.nix by poligle

{ config, pkgs, ... }:

{
    programs.zsh = {
        enable = true;
        enableCompletion = true;

    oh-my-zsh = {
        enable = true;
        theme = ""; 
        plugins = [
            "git"
            "sudo"
        ];
    };

    plugins = [
    {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
    }
    {
        name = "zsh-autosuggestions";
        src = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions";
    }
    {
        name = "zsh-syntax-highlighting";
        src = "${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting";
    }
    ];

    initContent = ''
        # Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
            source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi

        [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
    '';

    shellAliases = {
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
}

