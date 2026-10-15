#!/usr/bin/env bash

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/wofi.lock"
flock -n 9 || exit 0

readonly separator=$'\x1f'
readonly disableEntry="󰖪  Desactivar Wi-Fi"
readonly enableEntry="󰖩  Activar Wi-Fi"
readonly rescanEntry="󰑐  Buscar redes"
readonly editorEntry="󰒓  Configuración avanzada"

menu() {
	wofi --conf "$WIFI_MENU_CONF" --style "$WIFI_MENU_STYLE" --dmenu --prompt "$@"
}

notify() {
	notify-send -a wifi-menu -u low "Wi-Fi" "$1"
}

open_editor() {
	exec nm-connection-editor 9>&-
}

signal_icon() {
	local signal="${1:-0}"
	if [ "$signal" -ge 80 ] 2>/dev/null; then
		printf '%s' "󰤨"
	elif [ "$signal" -ge 60 ] 2>/dev/null; then
		printf '%s' "󰤥"
	elif [ "$signal" -ge 40 ] 2>/dev/null; then
		printf '%s' "󰤢"
	elif [ "$signal" -ge 20 ] 2>/dev/null; then
		printf '%s' "󰤟"
	else
		printf '%s' "󰤯"
	fi
}

ask_password() {
	menu "Contraseña de $1" --password < /dev/null
}

is_enterprise() {
	case "$1" in
		*802.1X*) return 0 ;;
		*) return 1 ;;
	esac
}

connect_saved() {
	local ssid="$1" security="$2" password

	nmcli connection up id "$ssid" >/dev/null 2>&1 && return 0

	if is_enterprise "$security"; then
		notify "No se ha podido conectar a $ssid; revisa sus credenciales"
		open_editor
	fi

	password="$(ask_password "$ssid")" || return 1
	[ -n "$password" ] || return 1
	nmcli connection modify id "$ssid" wifi-sec.psk "$password" >/dev/null 2>&1 || return 1
	nmcli connection up id "$ssid" >/dev/null 2>&1
}

connect_new() {
	local ssid="$1" security="$2" password

	if is_enterprise "$security"; then
		notify "$ssid usa WPA-Enterprise (p. ej. eduroam): créala en la configuración avanzada"
		open_editor
	fi

	if [ -z "$security" ] || [ "$security" = "--" ]; then
		nmcli device wifi connect "$ssid" >/dev/null 2>&1
		return
	fi

	password="$(ask_password "$ssid")" || return 1
	[ -n "$password" ] || return 1
	if ! nmcli device wifi connect "$ssid" password "$password" >/dev/null 2>&1; then
		nmcli connection delete id "$ssid" >/dev/null 2>&1
		return 1
	fi
}

while true; do
	if [ "$(nmcli -t -f WIFI general)" != "enabled" ]; then
		choice="$(printf '%s\n' "$enableEntry" | menu "Wi-Fi")" || exit 0
		[ "$choice" = "$enableEntry" ] && nmcli radio wifi on
		exit 0
	fi

	unset ssidOf securityOf seen
	declare -A ssidOf=() securityOf=() seen=()
	entries=("$disableEntry" "$rescanEntry")

	while IFS= read -r raw; do
		line="${raw//\\:/$separator}"
		inUse="${line%%:*}"
		rest="${line#*:}"
		signal="${rest%%:*}"
		rest="${rest#*:}"
		security="${rest%%:*}"
		ssid="${rest#*:}"
		ssid="${ssid//$separator/:}"

		[ -n "$ssid" ] || continue
		[ -z "${seen["$ssid"]:-}" ] || continue
		seen["$ssid"]=1

		entry="$(signal_icon "$signal")  $ssid"
		if [ -n "$security" ] && [ "$security" != "--" ]; then
			entry="$entry  󰌾"
		fi
		if [ "$inUse" = "*" ]; then
			entry="$entry  󰄬"
		fi

		ssidOf["$entry"]="$ssid"
		securityOf["$entry"]="$security"
		entries+=("$entry")
	done < <(nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan auto | sort -t: -k2,2nr)

	entries+=("$editorEntry")

	choice="$(printf '%s\n' "${entries[@]}" | menu "Wi-Fi")" || exit 0

	case "$choice" in
		"$disableEntry")
			nmcli radio wifi off
			exit 0
			;;
		"$rescanEntry")
			notify "Buscando redes…"
			nmcli device wifi list --rescan yes >/dev/null 2>&1
			continue
			;;
		"$editorEntry")
			open_editor
			;;
	esac

	ssid="${ssidOf["$choice"]:-}"
	[ -n "$ssid" ] || exit 0
	security="${securityOf["$choice"]:-}"

	if nmcli -g NAME connection show | grep -Fxq -- "$ssid"; then
		connect_saved "$ssid" "$security"
	else
		connect_new "$ssid" "$security"
	fi

	if [ "$?" -eq 0 ]; then
		notify "Conectado a $ssid"
	else
		notify "No se ha podido conectar a $ssid"
	fi
	exit 0
done
