# storage.nix by poligle

{ config, lib, pkgs, ... }:
{
    services.udisks2.enable = true;
    security.polkit.enable = true;

    security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject)
        {
            var mountActions =
            [
                "org.freedesktop.udisks2.filesystem-mount",
                "org.freedesktop.udisks2.filesystem-mount-system"
            ];

            if (mountActions.indexOf(action.id) >= 0 && subject.local && subject.active && subject.isInGroup("wheel"))
            {
                return polkit.Result.YES;
            }
        });
    '';
}
