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

{ config, lib, pkgs, ... }:
let
    flake = config.nihil.flake;

    nihil = pkgs.writeShellApplication
    {
        name = "nihil";
        runtimeInputs = [ pkgs.jq ];
        text = ''
            flake=''${NIHIL_FLAKE:-${flake}}

            # The configuration is named after the computer (settings.json's host).
            rebuild() {
                host=$(jq -r '.host.name // empty' "$flake/settings.json")
                sudo nixos-rebuild switch --flake "$flake#''${host:-$(hostname)}" "$@"
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
                version)
                    jq -r '.nodes.nihil.locked | "NIHIL \(.rev[0:7] // "local") (\(.lastModified // 0 | todate))"' "$flake/flake.lock"
                    ;;
                *)
                    echo "usage: nihil rebuild | update | settings | version | dev [path]"
                    echo "the machine's flake: $flake"
                    ;;
            esac
        '';
    };
in
{
    environment.systemPackages = [ nihil ];
}
