# boot-sound.nix by poligle
#
# A sound with the boot splash (sounds/nihil/boot.wav, from tools/sounds.py):
# soft ticks as the snowflake's LEDs switch on, then a chord. It plays once
# the computer's sound card is there, while Plymouth is still on screen, and
# never on a rebuild. PipeWire only starts with the session, so it goes
# through ALSA alone: on the first card with a playback device that is not a
# screen's (HDMI, DisplayPort), at a moderate level (the card's own levels
# are muted, or at nothing, until PipeWire sets them). Not when the session
# last left the sound muted or all the way down (services/Audio.qml writes
# that). settings.json's "bootSound": false turns it off.

{ config, lib, pkgs, ... }:
let
    user = config.nihil.user.name;
    silent = "${config.home-manager.users.${user}.xdg.stateHome}/nihil/silent";

    play = pkgs.writeShellScript "nihil-boot-sound" ''
        export PATH=${lib.makeBinPath [ pkgs.alsa-utils pkgs.gnugrep pkgs.coreutils ]}
        [ -e ${lib.escapeShellArg silent} ] && exit 0
        for pcm in /proc/asound/card*/pcm*p; do
            [ -d "$pcm" ] || continue
            grep -qiE 'hdmi|displayport' "$pcm/info" 2> /dev/null && continue
            card=''${pcm#/proc/asound/card}
            card=''${card%%/*}
            device=''${pcm##*/pcm}
            device=''${device%p}
            amixer -q -M -c "$card" sset Master 55% unmute 2> /dev/null || true
            for control in PCM Speaker Headphone; do
                amixer -q -M -c "$card" sset "$control" 100% unmute 2> /dev/null || true
            done
            exec aplay -q -D "plughw:$card,$device" ${../sounds/nihil/boot.wav}
        done
    '';
in
{
    options.nihil.bootSound = lib.mkOption
    {
        type = lib.types.bool;
        default = true;
        description = "A sound with the boot splash (modules/boot-sound.nix).";
    };

    config.systemd.services.nihil-boot-sound = lib.mkIf config.nihil.bootSound
    {
        description = "NIHIL: the sound of the boot splash";
        wantedBy = [ "sound.target" ];
        after = [ "sound.target" ];
        # Only while the splash is up: booting, not on a rebuild.
        unitConfig.ConditionPathExists = "/run/plymouth/pid";
        restartIfChanged = false;
        serviceConfig =
        {
            Type = "oneshot";
            ExecStart = play;
            TimeoutStartSec = 10;
        };
    };
}
