# nihil-cli.nix by poligle
#
# The nihil command, for the machine's flake (nihil.flake, /etc/nixos):
#
#   nihil rebuild     apply the machine's configuration
#   nihil update      bring the latest NIHIL (and what it pins), then rebuild
#   nihil settings    edit settings.json, then rebuild
#   nihil version     the NIHIL revision this machine runs
#   nihil dev [path]  rebuild with a local NIHIL checkout (here by default)
#                     instead of the one pinned, to try changes unpushed
#   nihil apply FILE  FILE (- for stdin) becomes settings.json, and the system
#                     is rebuilt in a unit of its own (Preferences uses it)
#   nihil passwd      change a password: the last line of stdin, user:password
#
# nihil apply's unit outlives whoever asked: the rebuild restarts the shell.
# /run/nihil tells how it goes: apply.status (running, done, warning or
# failed) and apply.log. A failed build puts the old settings.json back.

{ config, lib, pkgs, ... }:
let
    flake = config.nihil.flake;

    nihil = pkgs.writeShellApplication
    {
        name = "nihil";
        runtimeInputs = [ pkgs.jq pkgs.coreutils pkgs.gawk pkgs.shadow config.systemd.package ];
        text = ''
            flake=''${NIHIL_FLAKE:-${flake}}
            run=/run/nihil

            # The configuration is named after the computer (settings.json's host).
            rebuild() {
                host=$(jq -r '.host.name // empty' "$flake/settings.json")
                if [ "$(id -u)" = 0 ]; then
                    nixos-rebuild switch --flake "$flake#''${host:-$(hostname)}" "$@"
                else
                    sudo nixos-rebuild switch --flake "$flake#''${host:-$(hostname)}" "$@"
                fi
            }

            case "''${1:-help}" in
                rebuild)
                    shift
                    rebuild "$@"
                    ;;
                update)
                    shift
                    before=$(jq -r '.nodes.nihil.locked.rev // "?"' "$flake/flake.lock" 2>/dev/null || echo "?")
                    sudo nix flake update --flake "$flake"
                    after=$(jq -r '.nodes.nihil.locked.rev // "?"' "$flake/flake.lock" 2>/dev/null || echo "?")
                    if [ "$before" = "$after" ]; then
                        echo "NIHIL is up to date (''${after:0:7})."
                    else
                        echo "NIHIL ''${before:0:7} -> ''${after:0:7}"
                    fi
                    rebuild "$@"
                    ;;
                settings)
                    sudoedit "$flake/settings.json"
                    jq empty "$flake/settings.json" || { echo "settings.json is not valid JSON: nothing applied."; exit 1; }
                    rebuild
                    ;;
                dev)
                    shift
                    source=$(realpath "''${1:-.}")
                    if [ "$#" -gt 0 ]; then
                        shift
                    fi
                    if [ ! -f "$source/flake.nix" ]; then
                        echo "There is no NIHIL checkout in $source."
                        exit 1
                    fi
                    echo "NIHIL from $source, not the one pinned in $flake/flake.lock."
                    rebuild --override-input nihil "path:$source" --no-write-lock-file "$@"
                    ;;
                apply)
                    shift
                    if [ "$(id -u)" != 0 ]; then
                        exec sudo "$(readlink -f "$0")" apply "$@"
                    fi
                    if systemctl is-active --quiet nihil-apply.service; then
                        echo "Other settings are being applied."
                        exit 3
                    fi
                    mkdir -p "$run"
                    staged=$(mktemp)
                    trap 'rm -f "$staged"' EXIT
                    # From stdin, what comes before the JSON is left out: a
                    # password sudo did not need, when a finger did it.
                    if [ "''${1:--}" = - ]; then
                        awk 'started || /^[{]/ { started = 1; print }' > "$staged"
                    else
                        cat "$1" > "$staged"
                    fi
                    if ! jq -e 'type == "object" and .version == 1 and (.user.name | type == "string")
                        and (.host.name | type == "string" and length > 0 and length < 64
                            and (test("[^a-z0-9-]") | not) and (startswith("-") | not) and (endswith("-") | not))' \
                        "$staged" > /dev/null 2>&1; then
                        echo "Those settings are not valid."
                        exit 2
                    fi
                    install -m 0644 "$staged" "$run/settings.json"
                    echo running > "$run/apply.status"
                    : > "$run/apply.log"
                    chmod 0644 "$run/apply.status" "$run/apply.log"
                    systemd-run --unit nihil-apply --collect --quiet -E HOME=/root -- "$(readlink -f "$0")" apply-run
                    echo "Applying in nihil-apply.service: $run/apply.log tells how it goes."
                    ;;
                apply-run)
                    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
                    exec >> "$run/apply.log" 2>&1
                    before=$(readlink -f /run/current-system)
                    if [ -f "$flake/settings.json" ]; then
                        cp "$flake/settings.json" "$run/settings.previous.json"
                    fi
                    install -m 0644 "$run/settings.json" "$flake/settings.json"
                    status=0
                    rebuild || status=$?
                    if [ "$status" = 0 ]; then
                        echo "done" > "$run/apply.status"
                    elif [ "$(readlink -f /run/current-system)" != "$before" ]; then
                        # Switched, but some unit did not start.
                        echo warning > "$run/apply.status"
                    else
                        if [ -f "$run/settings.previous.json" ]; then
                            install -m 0644 "$run/settings.previous.json" "$flake/settings.json"
                        fi
                        echo failed > "$run/apply.status"
                    fi
                    ;;
                passwd)
                    if [ "$(id -u)" != 0 ]; then
                        exec sudo "$(readlink -f "$0")" passwd
                    fi
                    tail -n 1 | chpasswd
                    ;;
                version)
                    jq -r '.nodes.nihil.locked | "NIHIL \(.rev[0:7] // "local") (\(.lastModified // 0 | todate))"' "$flake/flake.lock"
                    ;;
                *)
                    echo "usage: nihil rebuild | update | settings | version | dev [path] | apply FILE | passwd"
                    echo "the machine's flake: $flake"
                    ;;
            esac
        '';
    };
in
{
    environment.systemPackages = [ nihil ];
}
