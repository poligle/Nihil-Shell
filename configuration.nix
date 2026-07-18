{ config, lib, pkgs, ... }:
{
  imports =
    [
      ./hardware-configuration.nix
    ];

  # Boot (UEFI + systemd-boot)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Red
  networking.hostName = "thinkpad";
  networking.networkmanager.enable = true;

  # Zona horaria y locale
  time.timeZone = "Europe/Madrid";
  i18n.defaultLocale = "es_ES.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    useXkbConfig = true;
  };

  # Teclado (gráfico + consola vía useXkbConfig)
  services.xserver.xkb.layout = "es";

  # Audio: PipeWire (y desactivar PulseAudio)
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Touchpad
  services.libinput.enable = true;

  # Swap comprimido en RAM
  zramSwap.enable = true;

  # Gráficos AMD
  hardware.graphics.enable = true;

  # Usuario
  users.users.poligle = {
    isNormalUser = true;
    description = "Pol";
    extraGroups = [ "wheel" "networkmanager" ];
    packages = with pkgs; [
      tree
    ];
  };

  programs.firefox.enable = true;

  # Paquetes del sistema
  environment.systemPackages = with pkgs; [
    neovim
    wget
    git
  ];

  # Permite software no libre
  nixpkgs.config.allowUnfree = true;

  # Flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # SSH
  services.openssh.enable = true;

  # --- Hyprland ---
  programs.hyprland.enable = true;
  programs.hyprland.withUWSM = false;

  # --- Display Manager: greetd + tuigreet ---
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd start-hyprland";
        user = "greeter";
      };
    };
  };

  # Variable de entorno para el escritorio (evita el aviso de start-hyprland)
  environment.sessionVariables = {
    XDG_CURRENT_DESKTOP = "Hyprland";
  };

  system.stateVersion = "26.05";
}
