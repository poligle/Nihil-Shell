# awww.nix by poligle

{ pkgs, ... }: {
  wayland.windowManager.hyprland.settings = {
    on = {
      _args = [
        "hyprland.start"
        ''
          function()
            -- Lanza el daemon y le pasa la imagen inyectada de forma segura por Nix
            hl.exec_cmd("awww-daemon")
            hl.exec_cmd("awww img ${./wallpapers/wallpaper.jpg}")
          end
        ''
      ];
    };
  };
}

