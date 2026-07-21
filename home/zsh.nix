# zsh.nix by poligle

{ config, pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableCompletion = true;

    oh-my-zsh = {
      enable = true;
      # 1. Deja el tema vacío para que cargue Powerlevel10k en su lugar de forma limpia
      theme = ""; 
      plugins = [
        "git"
        "sudo"
      ];
    };

    # 2. Inyectamos de forma nativa el tema interactivo Powerlevel10k
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

      # Carga tu configuración manual de p10k si ya existe
      [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
    '';

    shellAliases = {
      ll = "ls -l";
      update = "sudo nixos-rebuild switch --flake ~/nixos-config#thinkpad";
      clean = "sudo nix-collect-garbage --delete-old && sudo nixos-rebuild boot";
    };
  };
}

