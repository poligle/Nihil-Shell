# clipboard.nix by poligle
#
# The clipboard history (services/Clipboard.qml shows it, SUPER + V held):
# every copy, text or picture, kept by cliphist, as many as nihil.clipboard
# says (settings.json's "clipboard"; 0 turns the history off, and SUPER + V
# still pastes). What a password manager marks as sensitive is never kept.
#
#   nihil-clipboard list N           the newest N, as cliphist lists them, with
#                                    the pictures in $XDG_RUNTIME_DIR/nihil-clipboard
#   nihil-clipboard copy ID [TYPE]   put it back on the clipboard
#   nihil-clipboard paste ID [TYPE]  that, and paste it where the keyboard is
#   nihil-clipboard keys paste|copy  the window's own paste or copy: SHIFT or
#                                    CTRL + Insert
#   nihil-clipboard delete ID | wipe

{ config, osConfig, pkgs, lib, ... }:
let
	size = osConfig.nihil.clipboard;

	nihil-clipboard = pkgs.writeShellScriptBin "nihil-clipboard" ''
		set -u
		export PATH="${lib.makeBinPath [ pkgs.cliphist pkgs.wl-clipboard pkgs.wtype pkgs.coreutils pkgs.gnugrep osConfig.programs.hyprland.package ]}:$PATH"
		dir="''${XDG_RUNTIME_DIR:-/tmp}/nihil-clipboard"
		tab=$(printf '\t')

		# cliphist's line for an id, "<id>\t<preview>": decode and delete read
		# one as cliphist list gives it.
		entry() {
			cliphist list | while IFS= read -r found; do
				if [ "''${found%%"$tab"*}" = "$1" ]; then
					printf '%s\n' "$found"
					break
				fi
			done
		}

		# Back on the clipboard, as the type it was copied as.
		copy() {
			local found
			found=$(entry "$1")
			if [ -z "$found" ]; then
				echo "nihil-clipboard: no copy $1" >&2
				exit 1
			fi
			if [ -n "$2" ]; then
				printf '%s\n' "$found" | cliphist decode | wl-copy --type "$2"
			else
				printf '%s\n' "$found" | cliphist decode | wl-copy
			fi
		}

		# The window's own paste or copy: SHIFT + Insert and CTRL + Insert, as
		# GTK, Qt, browsers, Electron and kitty take them (home/kitty.nix),
		# where CTRL + V or C would not do in a terminal. Hyprland sends them
		# to the window with the keyboard, with that modifier alone whatever
		# else is held (hl.dsp.send_shortcut); wtype if it can't.
		keys() {
			local mods answer
			case "''${1:-}" in
				paste) mods=SHIFT ;;
				copy) mods=CTRL ;;
				*)
					echo "usage: nihil-clipboard keys paste|copy" >&2
					return 2
					;;
			esac
			answer=$(hyprctl dispatch "hl.dsp.send_shortcut({ mods = \"$mods\", key = \"Insert\" })" 2>&1)
			if [ "$answer" = ok ]; then
				return 0
			fi
			echo "nihil-clipboard: Hyprland said \"$answer\"; typing $mods + Insert with wtype" >&2
			if ! wtype -M "''${mods,,}" -k Insert -m "''${mods,,}"; then
				echo "nihil-clipboard: $mods + Insert could not be typed" >&2
				return 1
			fi
		}

		case "''${1:-}" in
			store)
				# wl-paste --watch runs this for each copy, with it on stdin.
				if [ "''${CLIPBOARD_STATE:-data}" != data ]; then
					cat > /dev/null
					exit 0
				fi
				# wl-paste hands over text when a copy has any: a picture copied
				# in a browser comes with its HTML. One with a picture and no
				# plain text is read again, as the picture.
				types=$(wl-paste --list-types 2> /dev/null || true)
				picture=""
				if ! printf '%s\n' "$types" | grep -q '^text/plain'; then
					picture=$(printf '%s\n' "$types" | grep -m 1 '^image/' || true)
				fi
				if [ -n "$picture" ]; then
					cat > /dev/null
					wl-paste --no-newline --type "$picture" | cliphist -max-items ${toString size} store
				else
					exec cliphist -max-items ${toString size} store
				fi
				;;
			list)
				# A picture's line says "[[ binary data 12 KiB png 640x480 ]]":
				# its file is decoded once, from its line, and the files of the
				# ones no longer listed go.
				mkdir -p "$dir"
				cliphist -preview-width 300 list | head -n "''${2:-${toString size}}" > "$dir/list.new"
				keep=" "
				while IFS="$tab" read -r id preview; do
					keep="$keep$id "
					if [[ $preview =~ ^\[\[\ binary\ data\ .*\ ([a-z]+)(\ [0-9]+x[0-9]+)?\ \]\]$ ]]; then
						file="$dir/$id.''${BASH_REMATCH[1]}"
						if [ ! -s "$file" ]; then
							printf '%s\t%s\n' "$id" "$preview" | cliphist decode > "$file.part" 2> /dev/null \
								&& mv "$file.part" "$file" || rm -f "$file.part"
						fi
					fi
				done < "$dir/list.new"
				for file in "$dir"/*.*; do
					[ -e "$file" ] || continue
					name=''${file##*/}
					case "$name" in list.new) continue ;; esac
					case "$keep" in *" ''${name%%.*} "*) ;; *) rm -f "$file" ;; esac
				done
				cat "$dir/list.new"
				;;
			copy)
				copy "''${2:?usage: nihil-clipboard copy ID [TYPE]}" "''${3:-}"
				;;
			paste)
				# Back on the clipboard, then the window's own paste.
				copy "''${2:?usage: nihil-clipboard paste ID [TYPE]}" "''${3:-}"
				sleep 0.06
				keys paste || exit 1
				;;
			keys)
				keys "''${2:-}" || exit $?
				;;
			delete)
				entry "''${2:?usage: nihil-clipboard delete ID}" | cliphist delete
				;;
			wipe)
				cliphist wipe
				rm -rf "$dir"
				;;
			*)
				echo "usage: nihil-clipboard list [N] | copy ID [TYPE] | paste ID [TYPE] | keys paste|copy | delete ID | wipe" >&2
				exit 2
				;;
		esac
	'';
in
{
	# Installed with the history off too: SUPER + V still pastes through it.
	home.packages = [ nihil-clipboard ];

	systemd.user.services.nihil-clipboard = lib.mkIf (size > 0)
	{
		Unit =
		{
			Description = "NIHIL clipboard history";
			After = [ "graphical-session.target" ];
			PartOf = [ "graphical-session.target" ];
		};

		Service =
		{
			ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --watch ${nihil-clipboard}/bin/nihil-clipboard store";
			Restart = "on-failure";
			RestartSec = 2;
		};

		Install.WantedBy = [ "graphical-session.target" ];
	};
}
