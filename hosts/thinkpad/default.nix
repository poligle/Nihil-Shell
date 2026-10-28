# default.nix by poligle (thinkpad)

{ config, lib, pkgs, ... }:
{
    imports = 
    [
        ./hardware-configuration.nix
        ../../modules/boot.nix
        ../../modules/network.nix
        ../../modules/locale.nix
        ../../modules/audio.nix
        ../../modules/hardware.nix
        ../../modules/users.nix
        ../../modules/packages.nix
        ../../modules/hyprland.nix
        ../../modules/regreet.nix
        ../../modules/desktop.nix
        ../../modules/storage.nix
        ../../modules/services.nix
        ../../modules/nix.nix
        ../../modules/plymouth.nix
        ../../modules/stylix.nix
        ../../modules/virtualisation.nix
        ../../modules/wireshark.nix
        ../../modules/direnv.nix
        ../../modules/nihil.nix
    ];
    programs.zsh.enable = true;
    
    # Host-specific
    networking.hostName = "thinkpad";

    # NIHIL: outputs at their logical size (after rotation), so the
    # dot-matrix wallpapers land on exact pixels. DP-1 is the vertical panel.
    nihil =
    {
        primaryOutput = "eDP-1";
        wallpaper = "night";
        outputs =
        {
            "eDP-1"    = { width = 1920; height = 1200; };
            "HDMI-A-1" = { width = 2560; height = 1440; };
            "DP-1"     = { width = 1080; height = 1920; bar = false; };
        };
    };
    system.stateVersion = "26.05";

    fileSystems = lib.genAttrs [ "/" "/home" "/nix" "/var/log" ] (_:
    {
        options = [ "compress=zstd" "noatime" ];
    });

    services.btrfs.autoScrub =
    {
        enable = true;
        fileSystems = [ "/" ];
    };
}
