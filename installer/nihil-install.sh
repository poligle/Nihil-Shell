# nihil-install by poligle (installer/iso.nix)
#
# NIHIL on a whole disk, or next to another system: GPT, a 1 GiB EFI
# partition (or the disk's own) and btrfs (inside LUKS if asked) with
# subvolumes for /, /home, /nix and /var/log. Next to another system it
# takes free space, or room a partition gives up: Windows' NTFS, an ext4 or
# a btrfs, shrunk keeping what they hold. Then the machine's flake goes to
# /etc/nixos: the template, settings.json with the answers and the screens
# found, and local.nix with the disk layout and the GPU's driver for the
# boot splash. NIHIL is pinned to the revision this image was built from;
# nihil update moves it on later.

template=/etc/nihil/template
source=$(cat /etc/nihil/source)
rev=$(cat /etc/nihil/rev)
lang=en

t() { if [ "$lang" = es ]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
say() { gum style --foreground 15 "$@"; }
dim() { gum style --foreground 7 "$@"; }
fail() { gum style --foreground 1 "$@" >&2; exit 1; }

if [ "$(id -u)" != 0 ]; then
    exec sudo "$0" "$@"
fi

trap 'gum style --foreground 1 "$(t "The installation stopped here. sudo nihil-install starts it again." \
    "La instalación se ha parado aquí. sudo nihil-install la vuelve a empezar.")" >&2' ERR

clear
gum style --foreground 15 --bold --margin "1 2" "N I H I L" "$(gum style --foreground 7 'ex nihilo')"

[ -d /sys/firmware/efi ] || fail "NIHIL boots with systemd-boot, which needs UEFI: this machine started in legacy BIOS mode."

language=$(gum choose --header "Language / Idioma" "English" "Español")
if [ "$language" = "Español" ]; then
    lang=es
    locale=es_ES.UTF-8
else
    locale=en_US.UTF-8
fi

# --- The USB stick ----------------------------------------------------------------

# The live system reads its programs from the stick as it needs them: one that
# cannot be read fails halfway, and only says that some program would not run.
# Read all of it now (that leaves it cached too).
if [ -f /iso/nix-store.squashfs ]; then
    if ! gum spin --title "$(t "Checking the USB stick…" "Comprobando el USB…")" -- cat /iso/nix-store.squashfs > /dev/null; then
        fail "$(t "The USB stick cannot be read whole. Write the image to it again, checking its SHA256 (SHA256SUMS, next to it on Releases), or try another stick or port; \"Copy ISO Files to RAM\", among the boot menu's options, reads it all into memory before starting." \
                  "No se puede leer el USB entero. Vuelve a grabar la imagen comprobando su SHA256 (SHA256SUMS, junto a ella en Releases), o prueba otro USB u otro puerto; «Copy ISO Files to RAM», en las opciones del menú de arranque, lo lee entero a memoria antes de empezar.")"
    fi
fi

# --- Network: the install downloads most of NIHIL --------------------------------

# Without a connection: a Wi-Fi network, again (a cable, or a phone sharing
# its connection over USB, work by themselves), or out to a shell.
until curl -fsI --max-time 6 https://cache.nixos.org >/dev/null; do
    if ! nmcli -t -f TYPE device 2>/dev/null | grep -qx wifi; then
        dim "$(t "No Wi-Fi card shows up (it may need a driver this image lacks). A cable, or a phone sharing its connection over USB, work too." \
                 "No aparece ninguna tarjeta Wi-Fi (puede que necesite un driver que esta imagen no trae). Un cable, o un móvil compartiendo la conexión por USB, también sirven.")"
    fi
    wifi=$(t "Choose a Wi-Fi network" "Elegir una red Wi-Fi")
    retry=$(t "Try again" "Probar otra vez")
    leave=$(t "Leave the installer" "Salir del instalador")
    case $(gum choose --header "$(t "There is no connection to the Internet." "No hay conexión a Internet.")" "$wifi" "$retry" "$leave") in
        "$wifi") nmtui-connect || true ;;
        "$leave")
            dim "$(t "sudo nihil-install starts it again; nmcli device lists the network cards." \
                     "sudo nihil-install lo vuelve a empezar; nmcli device muestra las tarjetas de red.")"
            exit 0
            ;;
        *) sleep 2 ;;
    esac
done

# --- Keyboard and time zone ------------------------------------------------------

layout=$(gum choose --header "$(t "Keyboard" "Teclado")" us es gb de fr it pt latam other)
if [ "$layout" = other ]; then
    layout=$(gum input --header "$(t "Keyboard layout (xkb name)" "Distribución del teclado (nombre xkb)")" --placeholder "br")
fi
loadkeys "$layout" >/dev/null 2>&1 || true

zone=$(curl -fs --max-time 6 https://ipapi.co/timezone || true)
if [ -z "$zone" ] || ! gum confirm "$(t "Time zone: $zone?" "Zona horaria: $zone?")" \
        --affirmative "$(t "Yes" "Sí")" --negative "$(t "Another" "Otra")"; then
    zone=$(timedatectl list-timezones | gum filter --header "$(t "Time zone" "Zona horaria")")
fi

# --- Who uses it -------------------------------------------------------------------

fullname=$(gum input --header "$(t "Your name" "Tu nombre")" --placeholder "Ada Lovelace")
suggested=$(printf '%s' "${fullname%% *}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
until [[ ${username:-} =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; do
    username=$(gum input --header "$(t "User name (lowercase letters and digits)" "Nombre de usuario (minúsculas y cifras)")" \
        --value "${suggested:-nihil}")
done
while true; do
    password=$(gum input --password --header "$(t "Password" "Contraseña")")
    again=$(gum input --password --header "$(t "Password, again" "La contraseña, otra vez")")
    if [ -n "$password" ] && [ "$password" = "$again" ]; then
        break
    fi
    dim "$(t "They don't match (or it's empty). Again." "No coinciden (o está vacía). Otra vez.")"
done
until [[ ${hostname:-} =~ ^[a-z0-9][a-z0-9-]{0,62}$ ]]; do
    hostname=$(gum input --header "$(t "Name of this computer" "Nombre de este ordenador")" --value "nihil")
done

# --- The disk ------------------------------------------------------------------------

# Disks worth installing on. lsblk calls a floppy (QEMU has one), zram,
# RAM disks and an eMMC's boot areas disks too: not those, not read-only
# ones, not the one this image runs from, and 20 GB or more.
live=$(lsblk -no PKNAME "$(findmnt -no SOURCE /iso 2>/dev/null || true)" 2>/dev/null || true)
# Listed in a variable, not a process substitution: if listing fails, the
# installer stops there and says so, rather than finding no disk.
listed=$(lsblk -dbnpo NAME,SIZE,RO,TYPE | awk -v live="/dev/$live" -v least=20000000000 '
    $4 == "disk" && $3 == 0 && $2 >= least && $1 != live &&
    $1 !~ /^\/dev\/(fd|zram|ram|loop)[0-9]/ && $1 !~ /(boot[0-9]+|rpmb)$/ { print $1 }')
[ -n "$listed" ] || fail "$(t "There is no disk of 20 GB or more to install on." "No hay ningún disco de 20 GB o más donde instalar.")"
mapfile -t found <<< "$listed"
disks=()
for candidate in "${found[@]}"; do
    disks+=("$candidate   $(lsblk -dno SIZE "$candidate" | tr -d ' ')   $(lsblk -dno MODEL "$candidate" | sed 's/ *$//')")
done
disk=$(gum choose --header "$(t "Install on" "Instalar en")" "${disks[@]}")
disk=${disk%% *}

# --- Where on the disk ---------------------------------------------------------------

# The whole disk, or next to what is on it: free space, or room a partition
# gives up, shrunk keeping what it holds (Windows' NTFS, an ext4 or a
# btrfs). cfdisk stays for doing it by hand, but it only edits the
# partition table: shrinking a partition there breaks what is inside. The
# boot menu goes on the disk's EFI partition, next to Windows' if there is
# one; if there is none, or it is small (Windows' is 100 MB), NIHIL adds
# 1 GB for the kernels (XBOOTLDR, with the EFI partition on /efi).
least=20000000000
bootBytes=1073741824
headroom=10000000000
sector=$(blockdev --getss "$disk")
align=$(( 1048576 / sector ))

size() { numfmt --to=si --suffix=B "$1"; }

part() {
    if [[ $disk =~ [0-9]$ ]]; then echo "${disk}p$1"; else echo "${disk}$1"; fi
}

gpt() { [ "$(blkid -o value -s PTTYPE "$disk" 2>/dev/null)" = gpt ]; }

# The number of partition $1 on the disk, as the kernel has it; its
# filesystem and label, read from the partition itself (udev may lag behind
# a partition table just changed).
number_of() { cat "/sys/class/block/${1##*/}/partition"; }
fstype_of() { blkid -p -o value -s TYPE "$1" 2>/dev/null || true; }
label_of() { blkid -p -o value -s LABEL "$1" 2>/dev/null || true; }

partitions() {
    lsblk -pbnro NAME,SIZE,TYPE "$disk" | awk -v least="$1" -v skip="$2" '$3 == "part" && $2 >= least && index(" " skip " ", " " $1 " ") == 0 { print $1 }'
}

describe() {
    local part
    for part in "$@"; do
        printf '%s   %s   %s\n' "$part" "$(lsblk -no SIZE "$part" | tr -d ' ')" "$(lsblk -no FSTYPE,LABEL "$part" | xargs)"
    done
}

# The disk's EFI partition, if it has one.
esp_of() {
    local part
    while read -r part; do
        if [ "$(blkid -p -o value -s PART_ENTRY_TYPE "$part" 2>/dev/null | tr '[:upper:]' '[:lower:]')" = c12a7328-f81f-11d2-ba4b-00a0c93ec93b ]; then
            echo "$part"
            return
        fi
    done < <(partitions 0 "")
}

# Whether Windows' boot manager is on the EFI partition $1.
has_windows() {
    local present=1
    [ -n "$1" ] || return 1
    mkdir -p /tmp/esp
    mount -o ro "$1" /tmp/esp 2>/dev/null || return 1
    if [ -d /tmp/esp/EFI/Microsoft ]; then
        present=0
    fi
    umount /tmp/esp
    return "$present"
}

# The first and last sector of each stretch of free space of at least $1
# bytes, aligned to 1 MiB.
free_stretches() {
    parted -m -s "$disk" unit s print free 2>/dev/null | awk -F: -v least="$1" -v align="$align" -v sector="$sector" '
        $5 == "free;" {
            first = int(($2 + align - 1) / align) * align
            last = int(($3 + 1) / align) * align - 1
            if (last > first && (last - first + 1) * sector >= least) print first, last
        }'
}

# How small the filesystem on $1 ($2) can get keeping what it holds, in
# bytes; or, if it cannot be shrunk now, why.
smallest() {
    local report magic blocks block
    case $2 in
        ntfs)
            magic=$( { ntfscat "$1" hiberfil.sys 2>/dev/null || true; } | head -c 4 | tr '[:upper:]' '[:lower:]')
            if [ "$magic" = hibr ]; then
                dim "$(t "$1: Windows is hibernated, or was shut down with fast startup. Turn fast startup off in Windows, shut it down, and start the installer again." \
                         "$1: Windows está hibernado, o se apagó con el inicio rápido. Desactívalo en Windows, apágalo y vuelve a empezar el instalador.")" >&2
                return 1
            fi
            if ! report=$(ntfsresize --info --no-progress-bar "$1" 2>&1); then
                dim "$(t "$1: its NTFS has to be checked first. Start Windows, restart it once, and start the installer again." \
                         "$1: su NTFS tiene que revisarse antes. Arranca Windows, reinícialo una vez y vuelve a empezar el instalador.")" >&2
                return 1
            fi
            sed -n 's/.*resize at \([0-9][0-9]*\) bytes.*/\1/p' <<< "$report"
            ;;
        ext4)
            report=$(resize2fs -P "$1" 2>/dev/null) || return 1
            blocks=$(sed -n 's/^Estimated minimum size of the filesystem: \([0-9][0-9]*\)$/\1/p' <<< "$report")
            block=$(dumpe2fs -h "$1" 2>/dev/null | awk -F: '/^Block size:/ { print $2 + 0 }')
            if [ -z "$blocks" ] || [ -z "$block" ]; then
                return 1
            fi
            echo $(( blocks * block ))
            ;;
        btrfs)
            mkdir -p /tmp/shrink
            mount -o ro "$1" /tmp/shrink 2>/dev/null || return 1
            report=$(btrfs inspect-internal min-dev-size /tmp/shrink 2>/dev/null) || report=""
            if [ "$(btrfs filesystem show /tmp/shrink 2>/dev/null | grep -c devid)" != 1 ]; then
                report=""
            fi
            umount /tmp/shrink
            if [ -z "$report" ]; then
                return 1
            fi
            echo "${report%% *}"
            ;;
        *)
            return 1
            ;;
    esac
}

# Partitions that can give NIHIL $1 bytes or more, as "partition filesystem
# bytes": what each can give keeping what it holds and 10 GB free.
givers() {
    local part bytes fstype small give
    while read -r part bytes; do
        fstype=$(fstype_of "$part")
        case $fstype in
            ntfs|ext4|btrfs) ;;
            *) continue ;;
        esac
        [ "$bytes" -gt $(( $1 + headroom )) ] || continue
        small=$(smallest "$part" "$fstype") || continue
        [ -n "$small" ] || continue
        give=$(( (bytes - small - headroom) / 1048576 * 1048576 ))
        if [ "$give" -ge "$1" ]; then
            printf '%s %s %s\n' "$part" "$fstype" "$give"
        fi
    done < <(lsblk -pbnro NAME,SIZE,TYPE "$disk" | awk '$3 == "part" { print $1, $2 }')
}

# How much room NIHIL takes, from $1 to $2 bytes.
how_much() {
    local fewest=$1 most=$2 amount typed choice labels=() all other
    all="$(t "All of it" "Todo"): $(size "$most")"
    other=$(t "Another amount" "Otra cantidad")
    for amount in 30 50 100 200 500; do
        if [ $(( amount * 1000000000 )) -ge "$fewest" ] && [ $(( amount * 1000000000 )) -lt "$most" ]; then
            labels+=("$amount GB")
        fi
    done
    choice=$(gum choose --header "$(t "Room for NIHIL" "Espacio para NIHIL")" "${labels[@]}" "$all" "$other") || return 1
    case $choice in
        "")
            return 1
            ;;
        "$all")
            echo "$most"
            ;;
        "$other")
            typed=""
            until [[ $typed =~ ^[1-9][0-9]*$ ]] && [ $(( typed * 1000000000 )) -ge "$fewest" ] && [ $(( typed * 1000000000 )) -le "$most" ]; do
                typed=$(gum input --placeholder 60 --header "$(t "GB for NIHIL, from $(( (fewest + 999999999) / 1000000000 )) to $(( most / 1000000000 ))" \
                    "GB para NIHIL, de $(( (fewest + 999999999) / 1000000000 )) a $(( most / 1000000000 ))")") || return 1
            done
            echo $(( typed * 1000000000 ))
            ;;
        *)
            echo $(( ${choice%% *} * 1000000000 ))
            ;;
    esac
}

# Next to what is on the disk: free space, or room a partition gives up.
# Fails, saying why, if there is none.
plan_room() {
    local entries=() labels=() index choice back need first last part fstype give label fstypes=""
    if ! gpt; then
        dim "$(t "$disk has no GPT partition table (an old Windows on MBR, or nothing yet): NIHIL can only go next to another system on GPT. Erase the whole disk, or convert it from Windows (mbr2gpt)." \
                 "$disk no tiene tabla de particiones GPT (un Windows antiguo en MBR, o nada aún): NIHIL solo puede ir junto a otro sistema en GPT. Borra el disco entero, o conviértelo desde Windows (mbr2gpt).")"
        return 1
    fi
    esp=$(esp_of)
    boot=$esp
    efi=""
    bootType=""
    if [ -z "$esp" ]; then
        bootType=ef00
    elif [ "$(blockdev --getsize64 "$esp")" -lt 500000000 ]; then
        bootType=ea00
        efi=$esp
    fi
    need=$least
    if [ -n "$bootType" ]; then
        need=$(( least + bootBytes ))
    fi
    windows=no
    if has_windows "$esp"; then
        windows=yes
    fi

    while read -r first last; do
        entries+=("free $first $last")
        labels+=("$(t "Its free space" "Su espacio libre"): $(size $(( (last - first + 1) * sector )))")
    done < <(free_stretches "$need")
    say "$(t "Looking at what its partitions hold…" "Mirando lo que guardan sus particiones…")"
    while read -r part fstype give; do
        label=$(label_of "$part")
        entries+=("shrink $part $fstype $give")
        labels+=("$(t "Room in" "Sitio en") $part ($fstype${label:+, $label}, $(size "$(blockdev --getsize64 "$part")")): $(t "up to" "hasta") $(size "$give")")
    done < <(givers "$need")
    while read -r part; do
        fstypes+="$(fstype_of "$part") "
    done < <(partitions 0 "")
    if [[ " $fstypes " == *" BitLocker "* ]]; then
        dim "$(t "Windows is encrypted with BitLocker, so it can only be shrunk from Windows (Disk Management, Shrink Volume); its free space then shows up here. Keep its recovery key at hand: Windows may ask for it." \
                 "Windows está cifrado con BitLocker, así que solo se puede encoger desde Windows (Administración de discos, Reducir volumen); su espacio libre aparece luego aquí. Ten a mano su clave de recuperación: Windows puede pedirla.")"
    fi
    if [ "${#entries[@]}" -eq 0 ]; then
        dim "$(t "There is no room for NIHIL next to what is on $disk: it needs $(size "$need")." \
                 "No hay sitio para NIHIL junto a lo que hay en $disk: necesita $(size "$need").")"
        return 1
    fi

    back=$(t "Back" "Volver")
    choice=$(gum choose --header "$(t "Where NIHIL goes" "Dónde va NIHIL")" "${labels[@]}" "$back") || return 1
    if [ -z "$choice" ] || [ "$choice" = "$back" ]; then
        return 1
    fi
    for index in "${!labels[@]}"; do
        if [ "${labels[$index]}" = "$choice" ]; then
            break
        fi
    done
    read -r room _ <<< "${entries[$index]}"
    if [ "$room" = free ]; then
        read -r room first last <<< "${entries[$index]}"
        roomBytes=$(how_much "$need" $(( (last - first + 1) * sector ))) || return 1
        roomBytes=$(( roomBytes / 1048576 * 1048576 ))
        roomFirst=$first
        roomLast=$(( first + roomBytes / sector - 1 ))
    else
        read -r room roomPart roomFs give <<< "${entries[$index]}"
        roomBytes=$(how_much "$need" "$give") || return 1
        roomBytes=$(( roomBytes / 1048576 * 1048576 ))
    fi
}

# On one of the disk's partitions, formatted (and one for booting, if the
# disk's EFI partition is missing or small).
plan_partition() {
    local roots=() boots=() choices=()
    if ! gpt; then
        dim "$(t "$disk has no GPT partition table: make one in cfdisk, or erase the whole disk." "$disk no tiene tabla de particiones GPT: créala en cfdisk o borra el disco entero.")"
        return 1
    fi
    esp=$(esp_of)
    mapfile -t roots < <(partitions "$least" "$esp")
    if [ "${#roots[@]}" -eq 0 ]; then
        dim "$(t "No partition of 20 GB or more: make room for NIHIL instead." "No hay ninguna partición de 20 GB o más: haz sitio para NIHIL.")"
        return 1
    fi
    mapfile -t choices < <(describe "${roots[@]}")
    root=$(gum choose --header "$(t "NIHIL goes on (it will be formatted)" "NIHIL va en (se formateará)")" "${choices[@]}") || return 1
    root=${root%% *}
    boot=$esp
    efi=""
    if [ -z "$esp" ] || [ "$(blockdev --getsize64 "$esp")" -lt 500000000 ]; then
        mapfile -t boots < <(partitions 500000000 "$esp $root")
        if [ "${#boots[@]}" -eq 0 ]; then
            dim "$(t "NIHIL also needs a partition of 1 GB for booting: make room for NIHIL instead." "NIHIL necesita también una partición de 1 GB para arrancar: haz sitio para NIHIL.")"
            return 1
        fi
        mapfile -t choices < <(describe "${boots[@]}")
        boot=$(gum choose --header "$(t "Boot partition (it will be formatted)" "Partición de arranque (se formateará)")" "${choices[@]}") || return 1
        boot=${boot%% *}
        efi=$esp
    fi
    windows=no
    if has_windows "$esp"; then
        windows=yes
    fi
}

# The filesystem on $1 ($2) made $3 bytes long, keeping what it holds.
shrink_filesystem() {
    local status=0
    case $2 in
        ntfs)
            printf 'y\n' | ntfsresize --no-progress-bar --size "$3" "$1" >/dev/null
            ;;
        ext4)
            e2fsck -f -p "$1" >/dev/null || status=$?
            [ "$status" -lt 4 ] || return 1
            resize2fs "$1" "$(( $3 / 1024 ))K" >/dev/null 2>&1
            ;;
        btrfs)
            mkdir -p /tmp/shrink
            mount "$1" /tmp/shrink
            btrfs filesystem resize "1:$3" /tmp/shrink >/dev/null
            umount /tmp/shrink
            ;;
    esac
}

# The entry of partition $1 made $2 bytes long, in place: same start, type,
# GUID, name and attributes. Prints the stretch it freed, first and last
# sector.
shrink_partition() {
    local number info code guid first last name attributes bit end flags=()
    number=$(number_of "$1")
    info=$(sgdisk -i "$number" "$disk")
    code=$(awk '/^Partition GUID code:/ { print $4 }' <<< "$info")
    guid=$(awk '/^Partition unique GUID:/ { print $4 }' <<< "$info")
    first=$(awk '/^First sector:/ { print $3 }' <<< "$info")
    last=$(awk '/^Last sector:/ { print $3 }' <<< "$info")
    attributes=$(awk '/^Attribute flags:/ { print $3 }' <<< "$info")
    name=$(sed -n "s/^Partition name: '\(.*\)'$/\1/p" <<< "$info")
    # Nothing is deleted unless all of the entry was read back.
    if [ -z "$code" ] || [ -z "$guid" ] || [ -z "$first" ] || [ -z "$last" ] || [[ ! $attributes =~ ^[0-9A-Fa-f]{16}$ ]]; then
        fail "$(t "Could not read the entry of $1; nothing was changed in the partition table." "No se pudo leer la entrada de $1; no se ha cambiado nada en la tabla de particiones.")"
    fi
    end=$(( first + $2 / sector - 1 ))
    for (( bit = 0; bit < 64; bit++ )); do
        if (( (16#$attributes >> bit) & 1 )); then
            flags+=(-A "$number:set:$bit")
        fi
    done
    sgdisk -a 1 -d "$number" -n "$number:$first:$end" -t "$number:$code" -u "$number:$guid" -c "$number:$name" "${flags[@]}" "$disk" >/dev/null
    partprobe "$disk" || true
    udevadm settle
    echo "$(( (end + align) / align * align )) $last"
}

# The lowest partition number the disk does not use yet.
free_number() {
    sgdisk -p "$disk" | awk '$1 ~ /^[0-9]+$/ { used[$1] = 1 } END { n = 1; while (n in used) n++; print n }'
}

# NIHIL's partitions from sector $1 to $2: first 1 GB for booting if the
# disk needs it, then the root.
make_partitions() {
    local first=$1 number
    if [ -n "$bootType" ]; then
        number=$(free_number)
        sgdisk -n "$number:$first:$(( first + bootBytes / sector - 1 ))" -t "$number:$bootType" -c "$number:NIHIL" "$disk" >/dev/null
        boot=$(part "$number")
        first=$(( first + bootBytes / sector ))
    fi
    number=$(free_number)
    sgdisk -n "$number:$first:$2" -t "$number:8300" -c "$number:nixos" "$disk" >/dev/null
    root=$(part "$number")
    partprobe "$disk" || true
    udevadm settle
}

mode=whole
esp=""
efi=""
boot=""
root=""
windows=no
room=""
roomPart=""
roomFs=""
roomBytes=0
roomFirst=0
roomLast=0
bootType=""
nextTo=$(t "Next to what is on it (make room)" "Junto a lo que hay (hacer sitio)")
all=$(t "Erase the whole disk" "Borrar el disco entero")
pick=$(t "On one of its partitions (formatting it)" "En una de sus particiones (formateándola)")
edit=$(t "Edit its partitions by hand (cfdisk)" "Editar sus particiones a mano (cfdisk)")
while true; do
    lsblk -o NAME,SIZE,FSTYPE,LABEL "$disk"
    choice=$(gum choose --header "$(t "Where on $disk" "Dónde en $disk")" "$nextTo" "$all" "$pick" "$edit")
    case $choice in
        "$nextTo")
            if plan_room; then
                mode=room
                break
            fi
            ;;
        "$all")
            mode=whole
            break
            ;;
        "$pick")
            if plan_partition; then
                mode=part
                break
            fi
            ;;
        "$edit")
            if gum confirm "$(t "cfdisk only edits the partition table: shrinking a partition there breaks what it holds, Windows too. To make room, use the first option. Open it anyway?" \
                    "cfdisk solo edita la tabla de particiones: encoger ahí una partición rompe lo que guarda, Windows también. Para hacer sitio, usa la primera opción. ¿Abrirlo igualmente?")" \
                    --affirmative "$(t "Open cfdisk" "Abrir cfdisk")" --negative "$(t "Back" "Volver")" --default=false; then
                cfdisk "$disk" || true
                partprobe "$disk" || true
                udevadm settle
            fi
            ;;
    esac
done

encrypt=no
if gum confirm "$(t "Encrypt the disk? It asks for a passphrase at every boot." "¿Cifrar el disco? Pedirá una contraseña en cada arranque.")" \
        --affirmative "$(t "Encrypt" "Cifrar")" --negative "$(t "No" "No")" --default=false; then
    encrypt=yes
    while true; do
        passphrase=$(gum input --password --header "$(t "Disk passphrase" "Contraseña del disco")")
        again=$(gum input --password --header "$(t "Disk passphrase, again" "La contraseña del disco, otra vez")")
        if [ -n "$passphrase" ] && [ "$passphrase" = "$again" ]; then
            break
        fi
        dim "$(t "They don't match (or it's empty). Again." "No coinciden (o está vacía). Otra vez.")"
    done
fi

if [ "$mode" = whole ]; then
    gum style --foreground 1 --margin "1 0" "$(t "Everything on $disk will be erased." "Se borrará todo lo que hay en $disk.")"
elif [ "$mode" = room ] && [ "$room" = shrink ]; then
    gum style --foreground 1 --margin "1 0" \
        "$(t "$roomPart will give $(size "$roomBytes") to NIHIL, keeping what it holds; the rest of $disk stays as it is." \
             "$roomPart cederá $(size "$roomBytes") a NIHIL, conservando lo que guarda; el resto de $disk se queda como está.")" \
        "$(t "Shrinking is safe, but a power cut halfway is not: keep a copy of what matters on it." \
             "Encoger es seguro, pero un corte de luz a medias no: ten copia de lo importante.")"
    if [ "$roomFs" = ntfs ]; then
        dim "$(t "Windows will check its disk the first time it starts: let it finish." "Windows revisará su disco la primera vez que arranque: déjale terminar.")"
    fi
elif [ "$mode" = room ]; then
    gum style --foreground 1 --margin "1 0" "$(t "NIHIL goes in $(size "$roomBytes") of free space on $disk; the rest stays as it is." \
        "NIHIL va en $(size "$roomBytes") de espacio libre de $disk; el resto se queda como está.")"
else
    gum style --foreground 1 --margin "1 0" "$(t "$root will be formatted" "Se formateará $root")$( [ "$boot" = "$esp" ] || printf ', %s' "$boot")$(t "; the rest of $disk stays as it is." "; el resto de $disk se queda como está.")"
fi
if [ "$mode" != whole ] && [ "$windows" = yes ]; then
    dim "$(t "The boot menu will offer Windows too." "El menú de arranque ofrecerá también Windows.")"
fi
gum confirm "$(t "Install NIHIL?" "¿Instalar NIHIL?")" --affirmative "$(t "Install" "Instalar")" --negative "$(t "Cancel" "Cancelar")" \
    --default=false || exit 1

# --- Partitions, btrfs, subvolumes ------------------------------------------------------

say "$(t "Preparing the disk…" "Preparando el disco…")"
umount -R /mnt 2>/dev/null || true
cryptsetup close cryptroot 2>/dev/null || true
if [ "$mode" = whole ]; then
    wipefs -af "$disk" >/dev/null
    sgdisk --zap-all "$disk" >/dev/null
    sgdisk -n1:0:+1G -t1:ef00 -c1:BOOT -n2:0:0 -t2:8300 -c2:nixos "$disk" >/dev/null
    partprobe "$disk"
    udevadm settle
    boot=$(part 1)
    root=$(part 2)
    mkfs.fat -F 32 -n BOOT "$boot" >/dev/null
else
    # Next to another system, the room first: free space, or what a
    # partition gives up, shrunk keeping what it holds.
    if [ "$mode" = room ]; then
        if [ "$room" = shrink ]; then
            say "$(t "Shrinking $roomPart: it can take a few minutes…" "Encogiendo $roomPart: puede tardar unos minutos…")"
            partBytes=$(blockdev --getsize64 "$roomPart")
            keep=$(( (partBytes - roomBytes) / 1048576 * 1048576 ))
            shrink_filesystem "$roomPart" "$roomFs" "$keep"
            stretch=$(shrink_partition "$roomPart" "$keep")
            read -r roomFirst roomLast <<< "$stretch"
        fi
        make_partitions "$roomFirst" "$roomLast"
    fi
    # The partitions chosen, typed for what they hold: Linux for the root,
    # EFI or XBOOTLDR (next to a small EFI partition) for the boot one. One
    # sgdisk for both: each run makes the kernel read the table again, and
    # the partitions are gone for a moment.
    types=(-t "$(number_of "$root"):8300")
    if [ "$boot" != "$esp" ]; then
        if [ -n "$esp" ]; then type=ea00; else type=ef00; fi
        types+=(-t "$(number_of "$boot"):$type")
    fi
    sgdisk "${types[@]}" "$disk" >/dev/null
    partprobe "$disk" || true
    udevadm settle
    if [ "$boot" != "$esp" ]; then
        mkfs.fat -F 32 -n NIHIL "$boot" >/dev/null
    fi
    wipefs -af "$root" >/dev/null
fi
if [ "$encrypt" = yes ]; then
    printf '%s' "$passphrase" | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$root"
    printf '%s' "$passphrase" | cryptsetup open --key-file=- "$root" cryptroot
    root=/dev/mapper/cryptroot
fi
mkfs.btrfs -f -L nixos "$root" >/dev/null

mount "$root" /mnt
for volume in @ @home @nix @log; do
    btrfs subvolume create "/mnt/$volume" >/dev/null
done
umount /mnt

options=compress=zstd,noatime
mount -o "subvol=@,$options" "$root" /mnt
mkdir -p /mnt/home /mnt/nix /mnt/var/log /mnt/boot
mount -o "subvol=@home,$options" "$root" /mnt/home
mount -o "subvol=@nix,$options" "$root" /mnt/nix
mount -o "subvol=@log,$options" "$root" /mnt/var/log
mount -o umask=0077 "$boot" /mnt/boot
if [ -n "$efi" ]; then
    mkdir -p /mnt/efi
    mount -o umask=0077 "$efi" /mnt/efi
fi

# --- The machine's flake ------------------------------------------------------------------

say "$(t "Writing this machine's configuration…" "Escribiendo la configuración de esta máquina…")"
nixos-generate-config --root /mnt >/dev/null
etc=/mnt/etc/nixos
rm -f "$etc/configuration.nix"
cp -r "$template/." "$etc/"
chmod -R u+w "$etc"

# Screens as the kernel sees them (Hyprland uses the same names), at their
# preferred mode; the welcome screen can change sizes and places later.
outputs='{}'
for connector in /sys/class/drm/card*-*; do
    [ "$(cat "$connector/status" 2>/dev/null)" = connected ] || continue
    name=${connector##*/}
    name=${name#card*-}
    mode=$(head -n 1 "$connector/modes" 2>/dev/null || true)
    [[ $mode =~ ^([0-9]+)x([0-9]+) ]] || continue
    outputs=$(jq --arg name "$name" --argjson width "${BASH_REMATCH[1]}" --argjson height "${BASH_REMATCH[2]}" \
        '. + { ($name): { width: $width, height: $height } }' <<< "$outputs")
done
[ "$outputs" != '{}' ] || outputs='{ "Virtual-1": { "width": 1920, "height": 1080 } }'

model=""
if grep -qi thinkpad /sys/class/dmi/id/product_version 2>/dev/null; then
    model=thinkpad
fi
fingerprint=false
if lsusb 2>/dev/null | grep -qiE 'fingerprint|synaptics.*(fp|finger)|goodix|elan.*fp|validity'; then
    fingerprint=true
fi

jq -n \
    --arg name "$username" --arg fullName "$fullname" --arg host "$hostname" \
    --arg language "$lang" --arg locale "$locale" --arg zone "$zone" \
    --arg layout "$layout" --arg model "$model" \
    --argjson outputs "$outputs" --argjson fingerprint "$fingerprint" \
    '{
        version: 1,
        user: { name: $name, fullName: $fullName },
        host: { name: $host },
        language: $language,
        locale: $locale,
        timeZone: $zone,
        keyboard: { layout: $layout, variant: "", model: $model },
        outputs: $outputs,
        wallpaper: "night",
        nilo: { enable: false, acceleration: "cpu", integratedGpu: false },
        fingerprint: $fingerprint,
        ssh: false
    }' > "$etc/settings.json"

# The GPU's driver in the initrd, so the boot splash shows from the start.
gpu=""
if lspci -nn | grep -Ei 'vga|3d|display' | grep -qiE 'amd|ati'; then
    gpu="hardware.amdgpu.initrd.enable = true;"
elif lspci -nn | grep -Ei 'vga|3d|display' | grep -qi intel; then
    gpu="boot.initrd.kernelModules = [ \"i915\" ];"
fi

# Next to another system: where systemd-boot and the kernels go, and
# Windows' clock, which it keeps in local time.
loader=""
if [ -n "$efi" ]; then
    loader+=$'\n\t# The EFI partition is small: systemd-boot there, the kernels on /boot (XBOOTLDR).'
    loader+=$'\n\tboot.loader.efi.efiSysMountPoint = lib.mkForce "/efi";'
    loader+=$'\n\tboot.loader.systemd-boot.xbootldrMountPoint = "/boot";\n'
fi
if [ "$windows" = yes ]; then
    loader+=$'\n\t# Windows keeps the hardware clock in local time.'
    loader+=$'\n\ttime.hardwareClockInLocalTime = true;\n'
fi

release=$(nixos-version | cut -d . -f 1,2)
cat > "$etc/local.nix" << EOF
# local.nix: NixOS settings of this machine only (drivers, services,
# packages). nihil-install wrote it; it's yours to change.

{ config, lib, pkgs, ... }:
{
	# The NixOS release this machine was installed with: keep it as it is.
	system.stateVersion = "$release";

	# Pictures in /etc/nixos/wallpapers become wallpapers too, drawn as dots.
	nihil.extraWallpapers = lib.optional (builtins.pathExists ./wallpapers) ./wallpapers;

	# btrfs, compressed, checked once a month (nihil-install's subvolumes).
	fileSystems = lib.genAttrs [ "/" "/home" "/nix" "/var/log" ] (_: { options = [ "compress=zstd" "noatime" ]; });
	services.btrfs.autoScrub = { enable = true; fileSystems = [ "/" ]; };

	${gpu}
${loader}
}
EOF

# The same NIHIL as this image (its revision), from the branch flake.nix names.
if [ -n "$rev" ]; then
    nix flake lock "$etc" --override-input nihil "$source/$rev"
else
    nix flake lock "$etc"
fi

# --- Install ------------------------------------------------------------------------------

say "$(t "Installing. This takes a while: most of it is downloaded." "Instalando. Tarda un rato: casi todo se descarga.")"
nixos-install --flake "$etc#$hostname" --no-root-passwd --no-channel-copy

printf '%s:%s\n' "$username" "$password" | nixos-enter --root /mnt -c chpasswd

gum style --foreground 15 --margin "1 0" "$(t "NIHIL is installed." "NIHIL está instalado.")"
if gum confirm "$(t "Restart now?" "¿Reiniciar ahora?")" --affirmative "$(t "Restart" "Reiniciar")" --negative "$(t "Later" "Luego")"; then
    umount -R /mnt
    [ "$encrypt" = no ] || cryptsetup close cryptroot
    reboot
fi
