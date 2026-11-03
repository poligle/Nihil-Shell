# iso.nix by poligle (installer)
#
# The installer: NixOS's minimal live image, which brings NetworkManager and
# linux-firmware, with the newest kernel, the NIHIL machine template and
# nihil-install, which starts by itself on the first console. It installs
# over the network: cache.nixos.org has almost all of NIHIL, and its own
# pieces (wallpapers, splash, fonts) are built there. Built by
# .github/workflows/release.yml.

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
    # The newest kernel (without ZFS, which lags behind it): the newest Wi-Fi
    # cards and GPUs need it.
    imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-minimal-new-kernel-no-zfs.nix" ];

    # NetworkManager drives Wi-Fi through networking.wireless (wpa_supplicant
    # over D-Bus) and turns it on itself: switching it off left nmtui with
    # cables only.
    networking.hostName = "nihil-installer";

    nix.settings.experimental-features = [ "nix-command" "flakes" ];

    environment.systemPackages = [ install pkgs.git ];

    # What nihil-install copies to /etc/nixos, and which NIHIL it pins.
    environment.etc =
    {
        "nihil/template".source = ../templates/machine;
        "nihil/source".text = "github:poligle/Nihil-Shell";
        "nihil/rev".text = nihil.rev or "";
    };

    console.font = "Lat2-Terminus16";

    # The live user logs in on its own; on the first console, the installer
    # starts, and leaving it gives a normal shell.
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
