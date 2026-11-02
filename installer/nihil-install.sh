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

until curl -fsI --max-time 6 https://cache.nixos.org >/dev/null; do
    dim "$(t "There is no connection to the Internet. Choose a network, or plug in a cable." \
             "No hay conexión a Internet. Elige una red o conecta un cable.")"
    nmtui-connect || true
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

# Every disk but the one this image runs from.
live=$(lsblk -no PKNAME "$(findmnt -no SOURCE /iso 2>/dev/null || true)" 2>/dev/null || true)
mapfile -t disks < <(lsblk -dnpo NAME,SIZE,MODEL,TYPE | awk -v live="/dev/$live" '$NF == "disk" && $1 != live { $NF = ""; print }')
[ "${#disks[@]}" -gt 0 ] || fail "$(t "No disk to install on." "No hay ningún disco donde instalar.")"
disk=$(gum choose --header "$(t "Install on (everything on it will be erased)" "Instalar en (se borrará todo lo que contiene)")" "${disks[@]}")
disk=${disk%% *}

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

gum style --foreground 1 --margin "1 0" "$(t "Everything on $disk will be erased." "Se borrará todo lo que hay en $disk.")"
gum confirm "$(t "Install NIHIL?" "¿Instalar NIHIL?")" --affirmative "$(t "Install" "Instalar")" --negative "$(t "Cancel" "Cancelar")" \
    --default=false || exit 1

# --- Partitions, btrfs, subvolumes ------------------------------------------------------

part() {
    if [[ $disk =~ [0-9]$ ]]; then echo "${disk}p$1"; else echo "${disk}$1"; fi
}

say "$(t "Preparing the disk…" "Preparando el disco…")"
umount -R /mnt 2>/dev/null || true
wipefs -af "$disk" >/dev/null
sgdisk --zap-all "$disk" >/dev/null
sgdisk -n1:0:+1G -t1:ef00 -c1:BOOT -n2:0:0 -t2:8300 -c2:nixos "$disk" >/dev/null
partprobe "$disk"
udevadm settle

boot=$(part 1)
root=$(part 2)
mkfs.fat -F 32 -n BOOT "$boot" >/dev/null
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
