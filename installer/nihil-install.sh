# nihil-install by poligle (installer/iso.nix)
#
# NIHIL on a whole disk: GPT, a 1 GiB EFI partition and the rest btrfs
# (inside LUKS if asked) with subvolumes for /, /home, /nix and /var/log.
# Then the machine's flake goes to /etc/nixos: the template, settings.json
# with the answers and the screens found, and local.nix with the disk
# layout and the GPU's driver for the boot splash. NIHIL is pinned to the
# revision this image was built from; nihil update moves it on later.

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
mapfile -t found < <(lsblk -dbnpo NAME,SIZE,RO,TYPE | awk -v live="/dev/$live" -v least=20000000000 '
    $4 == "disk" && $3 == 0 && $2 >= least && $1 != live &&
    $1 !~ /^\/dev\/(fd|zram|ram|loop)[0-9]/ && $1 !~ /(boot[0-9]+|rpmb)$/ { print $1 }')
[ "${#found[@]}" -gt 0 ] || fail "$(t "There is no disk of 20 GB or more to install on." "No hay ningún disco de 20 GB o más donde instalar.")"
disks=()
for candidate in "${found[@]}"; do
    disks+=("$candidate   $(lsblk -dno SIZE "$candidate" | tr -d ' ')   $(lsblk -dno MODEL "$candidate" | sed 's/ *$//')")
done
disk=$(gum choose --header "$(t "Install on" "Instalar en")" "${disks[@]}")
disk=${disk%% *}

# The disk, all of it, or one of its partitions, which can be made right
# here with cfdisk (in free space, or by deleting one). A partition keeps
# the rest of the disk as it is, and the boot menu goes on the disk's EFI
# partition, next to Windows' if there is one. If there is none, or it is
# small (Windows' is 100 MB), a second partition of 1 GB holds the kernels.
partitions() {
    lsblk -pbnro NAME,SIZE,TYPE "$disk" | awk -v least="$1" -v skip="$2" '$3 == "part" && $2 >= least && index(" " skip " ", " " $1 " ") == 0 { print $1 }'
}
describe() {
    local part
    for part in "$@"; do
        printf '%s   %s   %s\n' "$part" "$(lsblk -no SIZE "$part" | tr -d ' ')" "$(lsblk -no FSTYPE,LABEL "$part" | xargs)"
    done
}
mode=whole
efi=""
windows=no
edit=$(t "Make or delete partitions (cfdisk)" "Crear o borrar particiones (cfdisk)")
pick=$(t "Install on one of its partitions" "Instalar en una de sus particiones")
all=$(t "Erase the whole disk and install" "Borrar el disco entero e instalar")
while true; do
    lsblk -o NAME,SIZE,FSTYPE,LABEL "$disk"
    choice=$(gum choose --header "$(t "Partitions" "Particiones")" "$edit" "$pick" "$all")
    if [ "$choice" = "$edit" ]; then
        cfdisk "$disk" || true
        partprobe "$disk" || true
        udevadm settle
        continue
    fi
    [ "$choice" = "$pick" ] || break
    if [ "$(blkid -o value -s PTTYPE "$disk" 2>/dev/null)" != gpt ]; then
        dim "$(t "$disk has no GPT partition table: make one in cfdisk, or erase the whole disk." "$disk no tiene tabla de particiones GPT: créala en cfdisk o borra el disco entero.")"
        continue
    fi
    esp=$(lsblk -pnro NAME,PARTTYPE "$disk" | awk 'tolower($2) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" { print $1; exit }')
    mapfile -t roots < <(partitions 20000000000 "$esp")
    if [ "${#roots[@]}" -eq 0 ]; then
        dim "$(t "No partition of 20 GB or more: make one in cfdisk." "No hay ninguna partición de 20 GB o más: créala en cfdisk.")"
        continue
    fi
    mapfile -t choices < <(describe "${roots[@]}")
    root=$(gum choose --header "$(t "NIHIL goes on (it will be formatted)" "NIHIL va en (se formateará)")" "${choices[@]}")
    root=${root%% *}
    boot=$esp
    if [ -z "$esp" ] || [ "$(blockdev --getsize64 "$esp")" -lt 500000000 ]; then
        mapfile -t boots < <(partitions 500000000 "$esp $root")
        if [ "${#boots[@]}" -eq 0 ]; then
            dim "$(t "NIHIL also needs a partition of 1 GB for booting: make one in cfdisk." "NIHIL necesita también una partición de 1 GB para arrancar: créala en cfdisk.")"
            continue
        fi
        mapfile -t choices < <(describe "${boots[@]}")
        boot=$(gum choose --header "$(t "Boot partition (it will be formatted)" "Partición de arranque (se formateará)")" "${choices[@]}")
        boot=${boot%% *}
        efi=$esp
    fi
    if [ -n "$esp" ]; then
        mkdir -p /tmp/esp
        if mount -o ro "$esp" /tmp/esp 2>/dev/null; then
            [ ! -d /tmp/esp/EFI/Microsoft ] || windows=yes
            umount /tmp/esp
        fi
    fi
    mode=part
    break
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
else
    gum style --foreground 1 --margin "1 0" "$(t "$root will be formatted" "Se formateará $root")$( [ "$boot" = "$esp" ] || printf ', %s' "$boot")$(t "; the rest of $disk stays as it is." "; el resto de $disk se queda como está.")" \
        "$( [ "$windows" = no ] || t "The boot menu will offer Windows too." "El menú de arranque ofrecerá también Windows.")"
fi
gum confirm "$(t "Install NIHIL?" "¿Instalar NIHIL?")" --affirmative "$(t "Install" "Instalar")" --negative "$(t "Cancel" "Cancelar")" \
    --default=false || exit 1

# --- Partitions, btrfs, subvolumes ------------------------------------------------------

part() {
    if [[ $disk =~ [0-9]$ ]]; then echo "${disk}p$1"; else echo "${disk}$1"; fi
}

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
    # The partitions chosen, typed for what they hold: Linux for the root,
    # EFI or XBOOTLDR (next to a small EFI partition) for the boot one.
    sgdisk -t "$(lsblk -no PARTN "$root" | tr -d ' '):8300" "$disk" >/dev/null
    if [ "$boot" != "$esp" ]; then
        if [ -n "$esp" ]; then type=ea00; else type=ef00; fi
        sgdisk -t "$(lsblk -no PARTN "$boot" | tr -d ' '):$type" "$disk" >/dev/null
        mkfs.fat -F 32 -n NIHIL "$boot" >/dev/null
    fi
    partprobe "$disk" || true
    udevadm settle
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
