# clipboard.nix by poligle
#
# The clipboard history (services/Clipboard.qml shows it, SUPER + V): every
# copy, text or picture, kept by cliphist as wl-paste sees it, as many as
# nihil.clipboard says (settings.json's "clipboard"; 0 turns it off). What a
# password manager marks as sensitive is never kept.
#
#   nihil-clipboard list N         the newest N, as cliphist lists them, with
#                                  the pictures in $XDG_RUNTIME_DIR/nihil-clipboard
#   nihil-clipboard paste ID [TYPE] put it back on the clipboard and paste it
#                                  where the keyboard is (SHIFT + Insert)
#   nihil-clipboard delete ID | wipe

{ config, osConfig, pkgs, lib, ... }:
let
	size = osConfig.nihil.clipboard;

	nihil-clipboard = pkgs.writeShellScriptBin "nihil-clipboard" ''
		set -u
		export PATH="${lib.makeBinPath [ pkgs.cliphist pkgs.wl-clipboard pkgs.wtype pkgs.coreutils ]}:$PATH"
		dir="''${XDG_RUNTIME_DIR:-/tmp}/nihil-clipboard"
		tab=$(printf '\t')

		case "''${1:-}" in
			store)
				# wl-paste --watch runs this for each copy, with it on stdin.
				if [ "''${CLIPBOARD_STATE:-data}" = data ]; then
					exec cliphist -max-items ${toString size} store
				fi
				cat > /dev/null
				;;
			list)
				# A picture's line says "[[ binary data 12 KiB png 640x480 ]]":
				# its file is decoded once, by its id, and the files of the ones
				# no longer listed go.
				mkdir -p "$dir"
				cliphist -preview-width 300 list | head -n "''${2:-${toString size}}" > "$dir/list.new"
				keep=" "
				while IFS="$tab" read -r id preview; do
					keep="$keep$id "
					if [[ $preview =~ ^\[\[\ binary\ data\ .*\ ([a-z]+)(\ [0-9]+x[0-9]+)?\ \]\]$ ]]; then
						file="$dir/$id.''${BASH_REMATCH[1]}"
						if [ ! -s "$file" ]; then
							cliphist decode "$id" > "$file.part" 2> /dev/null && mv "$file.part" "$file" || rm -f "$file.part"
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
			paste)
				# Back on the clipboard, then SHIFT + Insert: it pastes in GTK, Qt,
				# browsers, Electron and kitty alike (home/kitty.nix), where
				# CTRL + V would not in a terminal.
				id=''${2:?usage: nihil-clipboard paste ID [TYPE]}
				if [ -n "''${3:-}" ]; then
					cliphist decode "$id" | wl-copy --type "$3"
				else
					cliphist decode "$id" | wl-copy
				fi
				sleep 0.06
				wtype -M shift -k Insert -m shift
				;;
			delete)
				id=''${2:?usage: nihil-clipboard delete ID}
				cliphist list | while IFS= read -r line; do
					if [ "''${line%%"$tab"*}" = "$id" ]; then
						printf '%s\n' "$line"
					fi
				done | cliphist delete
				;;
			wipe)
				cliphist wipe
				rm -rf "$dir"
				;;
			*)
				echo "usage: nihil-clipboard list [N] | paste ID [TYPE] | delete ID | wipe" >&2
				exit 2
				;;
		esac
	'';
in
lib.mkIf (size > 0)
{
	home.packages = [ nihil-clipboard ];

	systemd.user.services.nihil-clipboard =
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
