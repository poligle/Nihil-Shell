# boot.nix by poligle
{ config, lib, pkgs, ... }:
{
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.loader.systemd-boot.configurationLimit = 10;
    boot.supportedFilesystems = [ "exfat" "ext4" "vfat" ];
    services.udisks2.enable = true;
    services.gvfs.enable = true;
    boot.kernelParams = [
        "usb-storage.quirks=05e3:0747:u"
        "usbcore.quirks=05e3:0747:k"
    ]; 
}
