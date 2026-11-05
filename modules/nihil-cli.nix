# nihil-cli.nix by poligle
#
# The nihil command, for the machine's flake (nihil.flake, /etc/nixos):
#
#   nihil rebuild     apply the machine's configuration
#   nihil update      bring the latest NIHIL (and what it pins), then rebuild
#   nihil settings    edit settings.json, then rebuild
#   nihil version     the NIHIL this machine runs, and the one pinned
#   nihil dev [path]  NIHIL from a local checkout (here by default) instead of
#                     the one pinned, to try changes unpushed; it stays (nihil
#                     rebuild and Preferences use it too) until nihil dev off
#                     or nihil update. Each rebuild builds from a copy of it
#                     without .git (/var/lib/nihil/dev-tree)
#   nihil apply FILE  FILE (- for stdin) becomes settings.json, and the system
#                     is rebuilt in a unit of its own (Preferences uses it)
#   nihil passwd      change a password: the last line of stdin, user:password
#   nihil welcome     open the welcome again (to try it)
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
        runtimeInputs = [ pkgs.jq pkgs.coreutils pkgs.gawk pkgs.gnutar pkgs.shadow config.systemd.package ];
        text = ''
            flake=''${NIHIL_FLAKE:-${flake}}
            run=/run/nihil
            dev=/var/lib/nihil/dev
            tree=/var/lib/nihil/dev-tree

            as_root() {
                if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi
            }

            # nihil dev's checkout, while there is one.
            checkout() {
                if [ -f "$dev" ] && [ -f "$(cat "$dev")/flake.nix" ]; then
                    cat "$dev"
                fi
            }

            # The checkout as it is, untracked files included, without .git,
            # direnv's cache or build results: Nix copies all of a path: input
            # to the store whenever anything in it changes, and the history is
            # most of a checkout's size. A commit alone then changes nothing.
            snapshot() {
                as_root rm -rf "$tree.new" &&
                    as_root mkdir -p "$tree.new" &&
                    tar -C "$1" --exclude=.git --exclude=./.direnv --exclude=./result --exclude='./result-*' \
                        --exclude=__pycache__ -cf - . | as_root tar -C "$tree.new" -xf - &&
                    as_root rm -rf "$tree" &&
                    as_root mv "$tree.new" "$tree"
            }

            # The configuration is named after the computer (settings.json's host).
            rebuild() {
                local host from override=()
                host=$(jq -r '.host.name // empty' "$flake/settings.json")
                from=$(checkout)
                if [ -n "$from" ]; then
                    echo "NIHIL from $from (nihil dev off goes back to the one pinned)."
                    if ! snapshot "$from"; then
                        echo "Could not copy $from to $tree: nothing built." >&2
                        return 1
                    fi
                    override=(--override-input nihil "path:$tree" --no-write-lock-file)
                fi
                if [ "$(id -u)" = 0 ]; then
                    nixos-rebuild switch --flake "$flake#''${host:-$(hostname)}" "''${override[@]}" "$@"
                else
                    sudo nixos-rebuild switch --flake "$flake#''${host:-$(hostname)}" "''${override[@]}" "$@"
                fi
            }

            case "''${1:-help}" in
                rebuild)
                    shift
                    rebuild "$@"
                    ;;
                update)
                    shift
                    if [ -n "$(checkout)" ]; then
                        echo "Leaving nihil dev ($(checkout)) for the NIHIL on GitHub."
                        as_root rm -rf "$dev" "$tree" "$tree.new"
                    fi
                    before=$(jq -r '.nodes.nihil.locked.rev // "?"' "$flake/flake.lock" 2>/dev/null || echo "?")
                    # --refresh: Nix remembers for an hour which commit a
                    # branch was at, so a push just made would not be seen.
                    sudo nix flake update --refresh --flake "$flake"
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
                    if [ "''${1:-}" = off ]; then
                        shift
                        as_root rm -rf "$dev" "$tree" "$tree.new"
                        echo "NIHIL as pinned in $flake/flake.lock again."
                        rebuild "$@"
                        exit 0
                    fi
                    from=$(realpath "''${1:-.}")
                    if [ "$#" -gt 0 ]; then
                        shift
                    fi
                    if [ ! -f "$from/flake.nix" ]; then
                        echo "There is no NIHIL checkout in $from."
                        exit 1
                    fi
                    as_root mkdir -p "$(dirname "$dev")"
                    echo "$from" | as_root tee "$dev" > /dev/null
                    rebuild "$@"
                    ;;
                apply)
                    shift
                    if [ "$(id -u)" != 0 ]; then
                        exec sudo "$(readlink -f "$0")" apply "$@"
                    fi
                    # Anything failing here exits with 4: 1 is sudo's, for a
                    # wrong password (Preferences tells them apart).
                    trap 'exit 4' ERR
                    if systemctl is-active --quiet nihil-apply.service; then
                        echo "Other settings are being applied." >&2
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
                    # An object; the user's and the computer's names, when there,
                    # as NixOS takes them.
                    if ! jq -e 'type == "object"
                        and ((.user.name // "nihil") | type == "string" and test("^[a-z_][a-z0-9_-]*$"))
                        and ((.host.name // "nihil") | type == "string" and length > 0 and length < 64
                            and (test("[^a-z0-9-]") | not) and (startswith("-") | not) and (endswith("-") | not))' \
                        "$staged" > /dev/null 2>&1; then
                        echo "Those settings are not valid." >&2
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
                welcome)
                    exec nihil-ipc settings welcome
                    ;;
                version)
                    running=$(cat /etc/nihil/revision 2>/dev/null || echo "?")
                    pinned=$(jq -r '.nodes.nihil.locked | "\(.rev[0:7] // "local") (\(.lastModified // 0 | strftime("%Y-%m-%d %H:%M")))"' "$flake/flake.lock" 2>/dev/null || echo "?")
                    echo "NIHIL $running"
                    if [ -n "$(checkout)" ]; then
                        echo "  from $(checkout) (nihil dev; nihil dev off goes back to $pinned)"
                    elif [ "$pinned" != "$running" ]; then
                        echo "  $flake/flake.lock pins $pinned: nihil rebuild applies it"
                    fi
                    ;;
                *)
                    echo "usage: nihil rebuild | update | settings | version | dev [path|off] | apply FILE | passwd | welcome"
                    echo "the machine's flake: $flake"
                    ;;
            esac
        '';
    };
in
{
    options.nihil.revision = lib.mkOption
    {
        type = lib.types.str;
        default = "unknown";
        description = "The NIHIL this machine was built from, as nihil version says it (set by nihil.lib.mkSystem).";
    };

    config =
    {
        environment.systemPackages = [ nihil ];
        environment.etc."nihil/revision".text = config.nihil.revision + "\n";
    };
}
