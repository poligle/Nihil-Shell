# configuration.nix by poligle

{ config, lib, pkgs, ... }:
{
	imports = [
    		./hardware-configuration.nix
  	];

	# Boot (UEFI + systemd-boot)
  	boot.loader.systemd-boot.enable = true;
  	boot.loader.efi.canTouchEfiVariables = true;

    # ZSH shell 
    users.users.poligle.shell = pkgs.zsh;
    programs.zsh.enable = true;

  	# Network
  	networking.hostName = "thinkpad";
  	networking.networkmanager.enable = true;

  	# Bluetooth 
  	hardware.bluetooth.enable = true;
  	services.blueman.enable = true;

  	# Timezone & locale
  	time.timeZone = "Europe/Madrid";
  	i18n.defaultLocale = "es_ES.UTF-8";
  	console = {
  		font = "Lat2-Terminus16";
    		useXkbConfig = true;
  	};

  	# Keyboard Layout
  	services.xserver.xkb.layout = "es";

  	# Audio (PipeWire)
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

	# Fprintd
  	services.fprintd.enable = true;
	security.pam.services.hyprlock.fprintAuth = true;


  	# Swap compressed RAM
  	zramSwap.enable = true;

  	# Graphics
  	hardware.graphics.enable = true;

  	# User Configuration
  	users.users.poligle = {
    		isNormalUser = true;
    		description = "Pol";
    		extraGroups = [ "wheel" "networkmanager" "video" ];
    		packages = with pkgs; [
      			tree
    		];
  	};

  	programs.firefox.enable = true;

  	# System Pkgs
  	environment.systemPackages = with pkgs; [
		wev
    		wget
    		git
    		lxqt.lxqt-policykit
    		fastfetch
    		brightnessctl
		playerctl
    	];

  	# Allow Unfree Programs
  	nixpkgs.config.allowUnfree = true;

  	# Flakes
  	nix.settings.experimental-features = [ "nix-command" "flakes" ];

  	# SSH
  	services.openssh.enable = true;

  	# Fonts
  	fonts.packages = with pkgs; [
    		nerd-fonts.jetbrains-mono
   		nerd-fonts.hack
  	];

  	# Hyprland
  	programs.hyprland.enable = true;
  	programs.hyprland.withUWSM = true;

  	# Thunar
  	programs.thunar = {
    		enable = true;
    		plugins = with pkgs; [
      			thunar-archive-plugin
      			thunar-volman
    		];
  	};
  	services.gvfs.enable = true; 
  	services.tumbler.enable = true;

  	# Display Manager: greetd + tuigreet
  	services.greetd = {
    		enable = true;
    		settings = {
      			default_session = {
        			command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd 'uwsm start hyprland-uwsm.desktop'";
        			user = "greeter";
      			};
    		};
  	};

	nix = {
 		 # Automatic gen cleaning
		 gc = {
    			automatic = true;
    			dates = "weekly";
    			options = "--delete-older-than 7d";
  		};

  		# Automatic store optimizer 
		settings.auto-optimise-store = true;
	};
	


  	system.stateVersion = "26.05";
}

