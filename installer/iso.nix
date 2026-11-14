# iso.nix by poligle (installer)

{ config, lib, pkgs, modulesPath, nihil, ... }:
let
    install = pkgs.writeShellApplication
    {
        name = "nihil-install";
        runtimeInputs = with pkgs;
        [
            gum jq curl parted gptfdisk dosfstools btrfs-progs cryptsetup ntfs3g e2fsprogs
            util-linux pciutils usbutils kbd gnugrep gawk coreutils networkmanager
        ];
        text = builtins.readFile ./nihil-install.sh;
    };
in
{
    imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal-new-kernel-no-zfs.nix" ];

    networking.hostName = "nihil-installer";

    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    environment.systemPackages = [ install pkgs.git pkgs.iw ];

    environment.etc =
    {
        "nihil/template".source = ../templates/machine;
        "nihil/source".text = "github:poligle/Nihil-Shell";
        "nihil/rev".text = nihil.rev or "";
    };

    console.font = "Lat2-Terminus16";

    programs.bash.interactiveShellInit = ''
        if [ "$(tty)" = /dev/tty1 ] && [ -z "''${NIHIL_INSTALLER:-}" ]; then
            export NIHIL_INSTALLER=1
            sudo nihil-install || true
        fi
    '';

    services.getty.helpLine = lib.mkForce ''

        NIHIL installer. sudo nihil-install installs it; nmtui connects to a network.
    '';

    system.stateVersion = "26.05";
}
