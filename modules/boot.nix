# boot.nix by poligle
{ config, lib, pkgs, ... }:
{
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.systemd-boot.configurationLimit = 10;
    boot.supportedFilesystems = [ "exfat" "ext4" "vfat" ];
    services.udisks2.enable = true;
    services.gvfs.enable = true; 
}
