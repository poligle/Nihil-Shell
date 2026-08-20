# virtualisation.nix by poligle (deactivated for now)

{ config, pkgs, ... }:
{
    virtualisation.docker.enable = false;

    #boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
    #boot.binfmt.registrations."aarch64-linux" = 
    #{    
        #fixBinary = true;
    #};
}
