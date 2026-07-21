# nvim.nix by poligle

{ config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    
    viAlias = true;
    vimAlias = true;

    extraLuaConfig = ''
      -- Numbers and navigation
      vim.opt.number = true
      vim.opt.scrolloff = 8

      -- Indentation
      vim.opt.tabstop = 4
      vim.opt.shiftwidth = 4
      vim.opt.expandtab = true

      -- Basic UI
      vim.opt.termguicolors = true
      vim.opt.cursorline = true

      -- Search
      vim.opt.ignorecase = true
      vim.opt.smartcase = true

      -- Mouse
      vim.opt.mouse = "a"
    '';
  };
}
