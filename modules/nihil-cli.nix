# nihil-cli.nix by poligle

{ config, lib, pkgs, ... }:
let
    flake = config.nihil.flake;

    loader = config.boot.loader.systemd-boot;
    menu = if !loader.enable then 0 else if loader.configurationLimit == null then 100000 else loader.configurationLimit;

    nihil = pkgs.writeShellApplication
    {
        name = "nihil";
        runtimeInputs = [ pkgs.jq pkgs.coreutils pkgs.gawk pkgs.gnused pkgs.gnutar pkgs.curl pkgs.shadow config.systemd.package config.nix.package ];
        text = ''
            flake=''${NIHIL_FLAKE:-${flake}}
            run=/run/nihil
            dev=/var/lib/nihil/dev
            tree=/var/lib/nihil/dev-tree
            profile=''${NIHIL_PROFILE:-/nix/var/nix/profiles/system}
            menu=${toString menu}
            oneshot=''${NIHIL_ONESHOT:-/sys/firmware/efi/efivars/LoaderEntryOneShot-4a67b082-0a4c-41cf-b6c7-440b29bb8c4f}

            as_root() {
                if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi
            }

            checkout() {
                if [ -f "$dev" ] && [ -f "$(cat "$dev")/flake.nix" ]; then
                    cat "$dev"
                fi
            }

            snapshot() {
                as_root rm -rf "$tree.new" &&
                    as_root mkdir -p "$tree.new" &&
                    tar -C "$1" --exclude=.git --exclude=./.direnv --exclude=./result --exclude='./result-*' \
                        --exclude=__pycache__ -cf - . | as_root tar -C "$tree.new" -xf - &&
                    as_root rm -rf "$tree" &&
                    as_root mv "$tree.new" "$tree"
            }

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

            check() {
                local node rev owner repo ref api compare from
                node=$(jq -c '.nodes.nihil // {}' "$flake/flake.lock" 2> /dev/null || echo '{}')
                rev=$(jq -r 'if .locked.type == "github" then .locked.rev // "" else "" end' <<< "$node")
                owner=$(jq -r '.locked.owner // ""' <<< "$node")
                repo=$(jq -r '.locked.repo // ""' <<< "$node")
                ref=$(jq -r '.original.ref // ""' <<< "$node")
                from=$(checkout)
                if [ -z "$rev" ]; then
                    jq -n --arg dev "$from" '{ state: "unknown", dev: $dev }'
                    return
                fi
                api="https://api.github.com/repos/$owner/$repo"
                if [ -z "$ref" ]; then
                    ref=$(curl -fsSL --max-time 10 "$api" | jq -r '.default_branch // ""') || ref=""
                fi
                if [ -n "$ref" ] && compare=$(curl -fsSL --max-time 15 "$api/compare/$rev...$ref"); then
                    jq --arg dev "$from" --arg rev "$rev" --arg ref "$ref" '{
                        state: (if .ahead_by > 0 then "behind" else "current" end),
                        behind: .ahead_by,
                        pinned: $rev[0:7],
                        branch: $ref,
                        commits: [.commits | reverse | .[:20][] | { sha: .sha[0:7], subject: (.commit.message | split("\n")[0]) }],
                        dev: $dev
                    }' <<< "$compare"
                else
                    jq -n --arg dev "$from" --arg rev "$rev" '{ state: "offline", pinned: $rev[0:7], dev: $dev }'
                fi
            }

            numbers() {
                local link n
                for link in "$profile"-*-link; do
                    n=''${link#"$profile"-}
                    n=''${n%-link}
                    case $n in
                        "" | *[!0-9]*) continue ;;
                    esac
                    echo "$n"
                done | sort -n
            }

            number_of() {
                local name
                name=$(basename "$1")
                name=''${name#"$(basename "$profile")"-}
                echo "''${name%-link}"
            }

            is_generation() {
                case ''${1:-} in
                    "" | *[!0-9]*) return 1 ;;
                esac
                [ -L "$profile-$1-link" ]
            }

            generations() {
                local current default next n link path date version kernel revision dir free size
                current=$(readlink -f /run/current-system 2> /dev/null || true)
                default=$(number_of "$(readlink "$profile" 2> /dev/null || echo none)")
                next=""
                if [ -r "$oneshot" ]; then
                    next=$(tail -c +5 "$oneshot" | tr -d '\0' | sed -n 's/^nixos-generation-\([0-9]*\)\(\.conf\)\{0,1\}$/\1/p')
                fi
                read -r free size < <(df -B1 --output=avail,size /nix/store | tail -n 1) || true
                for n in $(numbers | sort -rn); do
                    link="$profile-$n-link"
                    path=$(readlink -f "$link")
                    date=$(stat -c %Y "$link")
                    version=$(cat "$path/nixos-version" 2> /dev/null || true)
                    kernel=""
                    for dir in "$path"/kernel-modules/lib/modules/*; do
                        if [ -d "$dir" ]; then
                            kernel=$(basename "$dir")
                            break
                        fi
                    done
                    revision=$(cat "$path/etc/nihil/revision" 2> /dev/null || true)
                    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$date" "$version" "$kernel" "$revision" "$path"
                done | jq -R -s --arg current "$current" --arg default "$default" --arg next "$next" \
                    --argjson menu "$menu" --argjson free "''${free:-0}" --argjson size "''${size:-0}" '
                    split("\n") | map(select(length > 0) | split("\t")) | to_entries | map(.key as $i | .value | {
                        number: (.[0] | tonumber),
                        date: (.[1] | tonumber),
                        nixos: .[2],
                        kernel: .[3],
                        nihil: (.[4] | split(" ")[0] // ""),
                        current: (.[5] == $current),
                        default: (.[0] == $default),
                        next: (.[0] == $next),
                        menu: ($i < $menu)
                    }) | { generations: ., bootMenu: ($menu > 0), free: $free, size: $size }'
            }

            changes() {
                local before="" n
                for n in $(numbers); do
                    if [ "$n" -lt "$1" ]; then
                        before=$n
                    fi
                done
                if [ -z "$before" ]; then
                    jq -n --argjson n "$1" '{ number: $n, before: null, lines: [] }'
                    return
                fi
                nix --extra-experimental-features nix-command store diff-closures "$profile-$before-link" "$profile-$1-link" \
                    | sed 's/\x1b\[[0-9;]*m//g' \
                    | jq -R -s --argjson n "$1" --argjson before "$before" '{ number: $n, before: $before, lines: (split("\n") | map(select(length > 0))) }'
            }

            boot_once() {
                local id
                id=$({ bootctl list --json=short 2> /dev/null || echo '[]'; } | jq -r --arg want "nixos-generation-$1" '
                    [ (if type == "array" then .[] else empty end) | .id // empty | select(ascii_downcase == $want or ascii_downcase == $want + ".conf") ][0] // empty')
                if [ -z "$id" ]; then
                    echo "The boot menu has no generation $1." >&2
                    exit 5
                fi
                bootctl set-oneshot "$id"
                echo "The next boot only, generation $1."
            }

            switch_to() {
                local previous before status=0
                previous=$(number_of "$(readlink "$profile")")
                before=$(readlink -f /run/current-system)
                echo "Generation $1, in place of $previous."
                if ! nix-env --profile "$profile" --switch-generation "$1"; then
                    return 1
                fi
                "$profile/bin/switch-to-configuration" switch || status=$?
                if [ "$status" != 0 ] && [ "$(readlink -f /run/current-system)" = "$before" ]; then
                    nix-env --profile "$profile" --switch-generation "$previous" || true
                fi
                return "$status"
            }

            clean() {
                local before after status=0
                before=$(df -B1 --output=avail /nix/store | tail -n 1 | tr -d ' ')
                if ! nix-collect-garbage --delete-older-than "$1"d; then
                    return 1
                fi
                "$profile/bin/switch-to-configuration" boot || status=$?
                sync -f /nix/store || true
                after=$(df -B1 --output=avail /nix/store | tail -n 1 | tr -d ' ')
                echo "nihil: freed $(( after > before ? after - before : 0 ))"
                return "$status"
            }

            in_unit() {
                local kind=$1
                shift
                if systemctl is-active --quiet nihil-apply.service; then
                    echo "Something is being applied already." >&2
                    exit 3
                fi
                mkdir -p "$run"
                echo running > "$run/apply.status"
                echo "$kind" > "$run/apply.kind"
                : > "$run/apply.log"
                chmod 0644 "$run/apply.status" "$run/apply.kind" "$run/apply.log"
                systemd-run --unit nihil-apply --collect --quiet -E HOME=/root -- "$(readlink -f "$0")" "$@"
                echo "In nihil-apply.service: $run/apply.log tells how it goes."
            }

            finish() {
                local status=$1 before=$2
                if [ "$status" = 0 ]; then
                    echo "done" > "$run/apply.status"
                elif [ "$(readlink -f /run/current-system)" != "$before" ]; then
                    echo warning > "$run/apply.status"
                else
                    echo failed > "$run/apply.status"
                fi
            }

            case "''${1:-help}" in
                rebuild)
                    shift
                    rebuild "$@"
                    ;;
                check)
                    shift
                    result=$(check)
                    if [ "''${1:-}" = --json ]; then
                        echo "$result"
                        exit 0
                    fi
                    case $(jq -r .state <<< "$result") in
                        behind)
                            jq -r '"GitHub has \(.behind) commit\(if .behind == 1 then "" else "s" end) past the NIHIL pinned (\(.pinned)):",
                                (.commits[] | "  \(.sha)  \(.subject)"),
                                "nihil update brings \(if .behind == 1 then "it" else "them" end)."' <<< "$result"
                            ;;
                        current) echo "NIHIL is up to date ($(jq -r .pinned <<< "$result"))." ;;
                        offline) echo "GitHub can't be reached: no way to know." ;;
                        *) echo "This NIHIL doesn't come from GitHub: nothing to compare." ;;
                    esac
                    if [ -n "$(checkout)" ]; then
                        echo "The system runs $(checkout) (nihil dev) meanwhile."
                    fi
                    ;;
                update)
                    shift
                    if [ "''${1:-}" = --unit ]; then
                        if [ "$(id -u)" != 0 ]; then
                            exec sudo "$(readlink -f "$0")" update --unit
                        fi
                        trap 'exit 4' ERR
                        if systemctl is-active --quiet nihil-apply.service; then
                            echo "Something is being applied already." >&2
                            exit 3
                        fi
                        mkdir -p "$run"
                        echo running > "$run/apply.status"
                        echo update > "$run/apply.kind"
                        : > "$run/apply.log"
                        chmod 0644 "$run/apply.status" "$run/apply.kind" "$run/apply.log"
                        systemd-run --unit nihil-apply --collect --quiet -E HOME=/root -- "$(readlink -f "$0")" update-run
                        echo "Updating in nihil-apply.service: $run/apply.log tells how it goes."
                        exit 0
                    fi
                    if [ -n "$(checkout)" ]; then
                        echo "Leaving nihil dev ($(checkout)) for the NIHIL on GitHub."
                        as_root rm -rf "$dev" "$tree" "$tree.new"
                    fi
                    before=$(jq -r '.nodes.nihil.locked.rev // "?"' "$flake/flake.lock" 2>/dev/null || echo "?")
                    as_root nix flake update --refresh --flake "$flake"
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
                generations)
                    shift
                    what=''${1:-list}
                    n=''${2:-}
                    case $what in
                        list | --json)
                            if [ "$what" = --json ] || [ "$n" = --json ]; then
                                generations
                                exit 0
                            fi
                            generations | jq -r '.generations[] | [
                                    "\(.number)",
                                    (.date | strflocaltime("%Y-%m-%d %H:%M")),
                                    (if .nixos != "" then "NixOS \(.nixos)" else empty end),
                                    (if .kernel != "" then "Linux \(.kernel)" else empty end),
                                    (if .nihil != "" then "NIHIL \(.nihil)" else empty end),
                                    ([ (if .current then "running" else empty end), (if .default then "boots" else empty end),
                                        (if .next then "the next boot" else empty end) ] | join(", "))
                                ] | map(select(. != "")) | join("  ")'
                            ;;
                        changes)
                            if ! is_generation "$n"; then
                                echo "There is no generation $n." >&2
                                exit 2
                            fi
                            changes "$n"
                            ;;
                        boot | switch | clean)
                            if [ "$(id -u)" != 0 ]; then
                                exec sudo "$(readlink -f "$0")" generations "$what" "$n" "''${3:-}"
                            fi
                            set -o errtrace
                            trap 'exit 4' ERR
                            if [ "$what" = clean ]; then
                                case $n in
                                    "" | *[!0-9]*) n=0 ;;
                                esac
                                if [ "$n" -lt 1 ] || [ "$n" -gt 3650 ]; then
                                    echo "Days, from 1 to 3650." >&2
                                    exit 2
                                fi
                            elif ! is_generation "$n"; then
                                echo "There is no generation $n." >&2
                                exit 2
                            fi
                            case $what:''${3:-} in
                                boot:*) boot_once "$n" ;;
                                switch:--unit) in_unit generation generations switch-run "$n" ;;
                                switch:*) switch_to "$n" ;;
                                clean:--unit) in_unit clean generations clean-run "$n" ;;
                                clean:*) clean "$n" ;;
                            esac
                            ;;
                        switch-run | clean-run)
                            export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
                            exec >> "$run/apply.log" 2>&1
                            before=$(readlink -f /run/current-system)
                            status=0
                            if [ "$what" = switch-run ]; then
                                switch_to "$n" || status=$?
                                echo "nihil: generation $(number_of "$(readlink "$profile")")"
                            else
                                clean "$n" || status=$?
                            fi
                            finish "$status" "$before"
                            ;;
                        *)
                            echo "usage: nihil generations [--json] | changes N | boot N | switch N [--unit] | clean DAYS [--unit]" >&2
                            exit 2
                            ;;
                    esac
                    ;;
                apply)
                    shift
                    if [ "$(id -u)" != 0 ]; then
                        exec sudo "$(readlink -f "$0")" apply "$@"
                    fi
                    trap 'exit 4' ERR
                    if systemctl is-active --quiet nihil-apply.service; then
                        echo "Other settings are being applied." >&2
                        exit 3
                    fi
                    mkdir -p "$run"
                    staged=$(mktemp)
                    trap 'rm -f "$staged"' EXIT
                    if [ "''${1:--}" = - ]; then
                        awk 'started || /^[{]/ { started = 1; print }' > "$staged"
                    else
                        cat "$1" > "$staged"
                    fi
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
                    echo settings > "$run/apply.kind"
                    : > "$run/apply.log"
                    chmod 0644 "$run/apply.status" "$run/apply.kind" "$run/apply.log"
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
                        echo warning > "$run/apply.status"
                    else
                        if [ -f "$run/settings.previous.json" ]; then
                            install -m 0644 "$run/settings.previous.json" "$flake/settings.json"
                        fi
                        echo failed > "$run/apply.status"
                    fi
                    ;;
                update-run)
                    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"
                    exec >> "$run/apply.log" 2>&1
                    before=$(readlink -f /run/current-system)
                    status=0
                    "$(readlink -f "$0")" update || status=$?
                    if [ "$status" = 0 ]; then
                        # Quoted: a bare done is the shell's keyword to shellcheck
                        echo "done" > "$run/apply.status"
                    elif [ "$(readlink -f /run/current-system)" != "$before" ]; then
                        echo warning > "$run/apply.status"
                    else
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
                watch)
                    shift
                    if ! command -v nihil-watch > /dev/null; then
                        echo "The deck is off: Preferences, Devices, Use devices (nihil.deck.enable)." >&2
                        exit 1
                    fi
                    exec nihil-watch "$@"
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
                    echo "usage: nihil rebuild | update [--unit] | check [--json] | settings | version | dev [path|off] | apply FILE | passwd | welcome | watch"
                    echo "       nihil generations [--json] | changes N | boot N | switch N [--unit] | clean DAYS [--unit]"
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

    options.nihil.cli = lib.mkOption
    {
        type = lib.types.package;
        readOnly = true;
        description = "The nihil command, as built.";
    };

    config =
    {
        nihil.cli = nihil;
        environment.systemPackages = [ nihil ];
        environment.etc."nihil/revision".text = config.nihil.revision + "\n";
    };
}
