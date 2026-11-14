# nihil-watch by poligle (home/deck/watch.nix): NIHIL for Wear OS on a watch,

repo=poligle/Nihil-Wear
package=com.nihilshell.wear
face=com.nihilshell.wear.watchface
provider=content://com.nihilshell.wear.shell
replaced=""

say() { printf '\n%s\n' "$*"; }
fail() { printf '%s\n' "$*" >&2; exit 1; }

watches() {
    local serial state
    while read -r serial state _; do
        [ "$state" = device ] || continue
        case $(adb -s "$serial" shell getprop ro.build.characteristics 2> /dev/null) in
            *watch*) echo "$serial" ;;
        esac
    done < <(adb devices | tail -n +2)
}

watch() {
    local found
    mapfile -t found < <(watches)
    case ${#found[@]} in
        0) return 1 ;;
        1) echo "${found[0]}" ;;
        *) fail "More than one watch on adb (${found[*]}): disconnect one (adb disconnect HOST:PORT)." ;;
    esac
}

service() {
    local type=$1 host=${2:-} found
    found=$(avahi-browse -rtp "$type" 2> /dev/null | awk -F';' '$1 == "=" && $3 == "IPv4" { print $8 ":" $9 }') || true
    if [ -z "$found" ]; then
        found=$(adb mdns services 2> /dev/null | awk -v type="$type." '$2 == type { print $3 }') || true
    fi
    if [ -n "$host" ]; then
        found=$(grep "^$host:" <<< "$found" || true)
    fi
    head -n 1 <<< "$found"
}

wait_for() {
    local type=$1 host=${2:-} seconds=$3 found=""
    for _ in $(seq "$seconds"); do
        found=$(service "$type" "$host")
        [ -n "$found" ] && break
        sleep 1
    done
    echo "$found"
}

pair() {
    local pairing code host connect
    say "On the watch: Developer options, Wireless debugging, Pair new device."
    echo "Looking for it on the network…"
    pairing=$(wait_for _adb-tls-pairing._tcp "" 90)
    if [ -z "$pairing" ]; then
        read -rp "Not found. The IP address and port under the code (HOST:PORT): " pairing
    else
        echo "Found at $pairing."
    fi
    read -rp "The Wi-Fi pairing code on the watch: " code
    adb pair "$pairing" "$code" || fail "adb could not pair: try again with a new code."
    host=${pairing%:*}
    connect=$(wait_for _adb-tls-connect._tcp "$host" 20)
    if [ -z "$connect" ]; then
        read -rp "The IP address and port on Wireless debugging's own screen (HOST:PORT): " connect
    fi
    adb connect "$connect" > /dev/null || fail "adb could not connect to $connect."
    for _ in $(seq 10); do
        watch > /dev/null && return 0
        sleep 1
    done
    fail "adb has $connect, but it doesn't say it's a watch."
}

download() {
    local dir=$1 release sums name url
    release=$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=20" |
        jq -c '[.[] | select(.draft | not)] | (map(select(.prerelease | not))[0] // .[0]) // empty') ||
        fail "GitHub didn't answer: try again in a moment."
    [ -n "$release" ] || fail "$repo has no release yet."
    say "$(jq -r '.name // .tag_name' <<< "$release")"
    sums=$(jq -r '.assets[] | select(.name == "SHA256SUMS") | .browser_download_url' <<< "$release")
    [ -n "$sums" ] || fail "The release has no SHA256SUMS: nothing installed."
    curl -fsSL -o "$dir/SHA256SUMS" "$sums" || fail "Could not download SHA256SUMS."
    while read -r _ name; do
        name=${name#\*}
        case $name in
            *.apk) ;;
            *) fail "SHA256SUMS names $name, not an APK: nothing installed." ;;
        esac
        case $name in */*) fail "SHA256SUMS names $name: nothing installed." ;; esac
        url=$(jq -r --arg name "$name" '.assets[] | select(.name == $name) | .browser_download_url' <<< "$release")
        [ -n "$url" ] || fail "The release has no $name: nothing installed."
        curl -fsSL -o "$dir/$name" "$url" || fail "Could not download $name."
    done < "$dir/SHA256SUMS"
    (cd "$dir" && sha256sum --quiet --strict -c SHA256SUMS) || fail "The APKs aren't what the release says: nothing installed."
}

install_one() {
    local serial=$1 apk=$2 id=$3 out answer
    echo "Installing $(basename "$apk")…"
    out=$(adb -s "$serial" install -r "$apk" 2>&1) && return 0
    case $out in
        *INSTALL_FAILED_UPDATE_INCOMPATIBLE*) ;;
        *) fail "The watch didn't take $(basename "$apk"): $out" ;;
    esac
    echo "The watch has $id signed with another key: a build of a checkout."
    read -rp "Replace it with the release? What it keeps, its pairing too, goes with it [y/N] " answer
    case $answer in
        [yYsS]*) ;;
        *) fail "Nothing replaced." ;;
    esac
    adb -s "$serial" uninstall "$id" > /dev/null || fail "The watch didn't let $id go."
    adb -s "$serial" install "$apk" > /dev/null || fail "The watch didn't take $(basename "$apk")."
    replaced=1
}

install_latest() {
    local serial=$1 dir apk
    dir=$(mktemp -d)
    download "$dir"
    for apk in "$dir"/*.apk; do
        case $apk in *-face-*) ;; *) install_one "$serial" "$apk" "$package" ;; esac
    done
    for apk in "$dir"/*.apk; do
        case $apk in *-face-*) install_one "$serial" "$apk" "$face" ;; esac
    done
    rm -rf "$dir"
}

call() {
    local serial=$1 method=$2 arg=${3:-} out
    if [ -n "$arg" ]; then
        out=$(adb -s "$serial" shell "content call --uri $provider --method $method --arg '$arg'")
    else
        out=$(adb -s "$serial" shell "content call --uri $provider --method $method")
    fi
    out=${out%$'\r'}
    case $out in
        "Result: Bundle[{"*"}]") ;;
        *) fail "The watch said: $out" ;;
    esac
    out=${out#"Result: Bundle[{"}
    out=${out%"}]"}
    echo "${out#*=}"
}

invite() {
    local serial=$1 uri name
    uri=$(nihil-deck pair --json | jq -r '.uri // empty') || true
    [ -n "$uri" ] || fail "The deck gave no invitation: is it on? (Preferences, Devices, Use devices)"
    name=$(call "$serial" invite "$uri")
    adb -s "$serial" shell input keyevent KEYCODE_WAKEUP
    adb -s "$serial" shell am start -n "$package/.ProbeActivity" > /dev/null
    echo "Invited by $name: the watch pairs with it now."
}

halo() {
    local serial=$1 service="$package/$package.system.HaloService" enabled
    adb -s "$serial" shell cmd notification allow_listener "$package/$package.system.GlyphListener"
    enabled=$(adb -s "$serial" shell settings get secure enabled_accessibility_services | tr -d '\r')
    case ":$enabled:" in
        *":$service:"*) ;;
        ":null:" | "::") adb -s "$serial" shell settings put secure enabled_accessibility_services "$service" ;;
        *) adb -s "$serial" shell settings put secure enabled_accessibility_services "$enabled:$service" ;;
    esac
    adb -s "$serial" shell settings put secure accessibility_enabled 1
}

case ${1:-install} in
    install)
        serial=$(watch) || { pair; serial=$(watch); }
        install_latest "$serial"
        invite "$serial"
        halo "$serial" || echo "The light on the edge could not be turned on: NIHIL's settings on the watch can."
        say "Done. On the watch, hold the face and choose NIHIL's."
        ;;
    update)
        serial=$(watch) || fail "No watch on adb: run nihil-watch to pair it."
        install_latest "$serial"
        if [ -n "$replaced" ]; then
            invite "$serial"
        fi
        say "Updated."
        ;;
    forget)
        serial=$(watch) || fail "No watch on adb: run nihil-watch to pair it."
        device=$(call "$serial" forget)
        if [ -n "$device" ] && nihil-deck forget "$device" > /dev/null; then
            echo "The watch and this computer have forgotten each other."
        else
            echo "The watch has forgotten its computer."
        fi
        ;;
    *)
        echo "nihil-watch [install | update | forget]" >&2
        exit 2
        ;;
esac
