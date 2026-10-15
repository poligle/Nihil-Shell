# nixos-config

![screenshot](.screenshots/screenshot.png)
![screenshot](.screenshots/screenshot2.png)
![screenshot](.screenshots/screenshot3.png)

Declarative NixOS configuration for `poligle@thinkpad`, based on Flakes, Home Manager and Stylix.
Desktop environment: **Hyprland** (configured natively in Nix using the Lua backend due to the recent update),
with the whole colour scheme generated from the current wallpaper.

---

## Overview

This repository holds the complete, reproducible configuration of my NixOS system.
Everything — packages, services, graphical environment, dotfiles, scripts and theming — is
defined declaratively, so the whole system can be rebuilt identically on any machine.

Migrated from Arch Linux + Hyprland (hyprlang) previous repository to NixOS + Hyprland (Lua).

---

## Structure

```
nixos-config/
├── flake.nix                 # Inputs (nixpkgs, home-manager, stylix) and outputs (hosts)
├── flake.lock                # Pinned exact versions (reproducibility)
├── home.nix                  # Home Manager index (imports home/*)
│
├── hosts/                    # Per-machine configuration
│   └── thinkpad/
│       ├── default.nix       # Imports modules + hostname + stateVersion
│       └── hardware-configuration.nix
│
├── modules/                  # Shared system modules (common across hosts)
│   ├── boot.nix              # systemd-boot (UEFI)
│   ├── plymouth.nix          # Boot splash, silent boot
│   ├── network.nix           # NetworkManager, Bluetooth, rtw89 workaround
│   ├── locale.nix            # Timezone, language, keyboard
│   ├── audio.nix             # PipeWire
│   ├── hardware.nix          # Touchpad, fprintd (off with the lid closed), zram, LED
│   ├── users.nix             # User and shell (zsh)
│   ├── packages.nix          # System packages, fonts, unfree
│   ├── hyprland.nix          # Hyprland compositor
│   ├── regreet.nix           # Display manager (greetd + ReGreet)
│   ├── desktop.nix           # Thunar, gvfs, tumbler, dconf
│   ├── storage.nix           # udisks2 + polkit rule (internal drives without password)
│   ├── services.nix          # SSH and other services
│   ├── stylix.nix            # Wallpaper, palette, fonts, cursor, opacity
│   ├── nix.nix               # Flakes, garbage collection,
│   └── virtualisation.nix    # Docker, arm64 (deactivated rn)
│
├── home/                     # User configuration (Home Manager)
│   ├── hyprland.nix          # Hyprland (Lua): binds, gestures, animations, rules
│   ├── waybar.nix            # Status bar (custom CSS driven by the Stylix palette)
│   ├── wofi.nix              # Launcher (custom CSS driven by the Stylix palette)
│   ├── kitty.nix             # Terminal
│   ├── hyprlock.nix          # Lock screen (password + fingerprint)
│   ├── hypridle.nix          # Idle daemon
│   ├── dunst.nix             # Notifications / OSD
│   ├── awww.nix              # Wallpaper daemon
│   ├── gtk.nix               # GTK settings and icon theme
│   ├── thunar.nix            # XFCE helper so Thunar opens kitty
│   ├── desktop-entries.nix   # Hides unwanted launcher entries
│   ├── zsh.nix               # Shell
│   ├── zen.nix               # Zen Browser
│   ├── eww.nix               # Widgets
│   ├── nvim.nix              # Editor
│   ├── vscode.nix            # Editor
│   ├── python.nix            # Python environment
│   ├── scripts.nix           # Own scripts, packaged
│   ├── wifi-menu.sh          # Wofi Wi-Fi menu (right click on the waybar icon)
│   ├── bluetooth.nix         # Blueman without auto power-on
│   ├── engineering.nix       # FHS environment + launchers for MATLAB, FEKO and ADS
│   ├── cli.nix               # CLI tooling (gh, lazygit, fzf, bat, tealdeer)
│   ├── refresh.nix           # Reloads Hyprland, waybar and eww after each switch
│   └── waybar-autohide.py    # Python auto-hide script for the bar
│
└── wallpapers/               # Wallpapers (versioned for cloning)
```

### Layered separation

- **`hosts/`** — What is specific to each machine (hardware, hostname).
- **`modules/`** — What is common to all machines (packages, services, environment).
- **`home/`** — The user configuration (declarative dotfiles).

Adding a new machine is just a matter of creating a `hosts/<name>/` that imports the
same shared modules plus its own `hardware-configuration.nix`.

---

## Theming

Colours are generated from the wallpaper by Stylix and applied system-wide: GTK, Qt,
kitty, dunst, hyprlock, Hyprland borders, VSCode, Plymouth, ReGreet and Zen.

**`modules/stylix.nix` is the single source of truth.** The wallpaper is declared once
there and everything else references it — `awww.nix` reads `config.stylix.image` to set
the desktop background, and hyprlock gets its background from Stylix directly. Wallpaper,
lock screen and palette cannot drift apart by construction.

### Changing the theme

```nix
# modules/stylix.nix
image = ../wallpapers/some-other.jpg;
```

Then rebuild. A reboot is the simplest way to see everything applied at once, since
waybar is launched by Hyprland rather than systemd and won't reload on its own.

The generated palette can be inspected at `/etc/stylix/palette.html` before committing
to a wallpaper. More colourful images tend to produce better palettes.

### Exceptions

- **waybar** and **wofi** keep their own CSS (`stylix.targets.*.enable = false`), but
  their colours are pulled from `config.lib.stylix.colors`. This preserves the custom
  layout — rounded module groups, icon-only launcher grid — while still following the
  wallpaper.
- **Icons** stay on Colloid regardless of the palette (`stylix.iconTheme` is opt-in and
  left off).
- **Obsidian** is not themed: Stylix has no target for it.

---

## Daily usage

Rebuild the system after editing the configuration:

```bash
sudo nixos-rebuild switch --flake ~/nixos-config#<name> # or with the alias nrebuild
```

`nh os switch` does the same and also prints the package diff between generations.

Validate the configuration without building:

```bash
nix flake check # or with the alias ncheck
```

Build without activating (to test changes safely):

```bash
sudo nixos-rebuild build --flake ~/nixos-config#<name>
```

Update packages (equivalent to `pacman -Syu` from Arch):

```bash
nix flake update # or with the alias nupdate
sudo nixos-rebuild switch --flake ~/nixos-config#thinkpad
```

Manually clean up old generations:

```bash
sudo nix-collect-garbage --delete-older-than 7d # or with the alias ngc
```

> Garbage collection also runs automatically on a weekly basis (see `modules/nix.nix`).

---

## Recovery

- **System won't boot:** pick an earlier generation from the boot menu (systemd-boot).
  It's a system-level restore point.
- **A configuration broke something:** roll the repository back to a previous commit
  with Git (`git log`, `git revert`, `git checkout`), fix it, and rebuild. Git versions
  the *code*; generations version the *system*.

---

## Cloning to a new machine

1. Install base NixOS and generate the new machine's hardware config:

   ```bash
   sudo nixos-generate-config --show-hardware-config > /tmp/hardware-configuration.nix
   ```

2. Clone this repository:

   ```bash
   git clone git@github.com:poligle/nixos-config
   cd nixos-config
   ```

3. Create the new host:

   ```bash
   mkdir -p hosts/<name>
   cp /tmp/hardware-configuration.nix hosts/<name>/
   cp hosts/thinkpad/default.nix hosts/<name>/default.nix
   # edit hosts/<name>/default.nix: adjust networking.hostName
   ```

4. Add the new configuration to `flake.nix`:

   ```nix
    nixosConfigurations.thinkpad = nixpkgs.lib.nixosSystem 
		{
			system = "x86_64-linux";
			modules = [
				./hosts/thinkpad/default.nix
                stylix.nixosModules.stylix

				home-manager.nixosModules.home-manager
				{
					home-manager.useGlobalPkgs = true;
					home-manager.useUserPackages = true;

          home-manager.extraSpecialArgs = { inherit inputs; };
					home-manager.users.poligle = ./home.nix;
				}
			];
		};
   ```

5. Build:

   ```bash
   git add .
   sudo nixos-rebuild switch --flake .#<name>
   ```

Local state is not part of the repository and has to be set up again on each machine:
user password (`passwd`), SSH keys, fingerprint enrollment (`fprintd-enroll`) and the
engineering installs (`~/eda`, `~/.config/eda/licenses.env`).

---

## Technical details

- **Filesystem:** btrfs with subvolumes (`@`, `@home`, `@nix`, `@log`), zstd compression
  and `noatime`. Swap via zram.
- **Boot:** UEFI + systemd-boot, Plymouth splash with silent boot kernel parameters.
- **Login:** greetd + ReGreet running in cage on the last connected monitor, themed by
  Stylix. The Spanish layout reaches cage through `XKB_DEFAULT_LAYOUT`.
- **Hyprland in Lua:** since version 0.55, Hyprland recommends Lua configuration. The
  whole config is declared in Nix (`wayland.windowManager.hyprland.settings`) and Home
  Manager generates `hyprland.lua`: every attribute becomes an `hl.<name>(...)` call,
  lists become one call per element, `_args` gives multi-argument calls and inline Lua
  goes through `lib.generators.mkLuaInline`. Stylix also writes into `settings.config`,
  so keys it already sets (border and shadow colours) need `lib.mkForce`. Under Lua,
  `hyprctl dispatch` takes Lua too: `hyprctl dispatch 'hl.dsp.dpms({ action = "off" })'`.
- **Live refresh:** after every switch, `home/refresh.nix` reloads Hyprland and restarts
  waybar (with its auto-hide) and the eww widgets inside the running session, because
  none of them notice that their config symlink now points to a new store path.
- **Own scripts:** packaged with `writeShellScriptBin` and their dependencies declared
  explicitly, for full reproducibility: `waybar-autohide`, `mic-led-sync`, `osd-volume`,
  `osd-brightness`, `wifi-menu`, `wifi-status`, `bluetooth-status`.
- **Engineering software:** GNU Octave and Python (numpy, scipy, matplotlib, scikit-rf)
  are declarative. MATLAB, Altair FEKO and Keysight ADS can't be packaged (licensing,
  opaque dependencies), so `home/engineering.nix` provides `eda-fhs`, an FHS sandbox with
  the libraries they expect, plus `matlab`, `feko` and `ads` launchers and menu entries.
  Each one is installed from inside `eda-fhs` into `~/eda/{matlab,altair,keysight/ads}`;
  licence servers go in `~/.config/eda/licenses.env`, which stays out of the repo.

 ---

## Notes

Public repository: contains no secrets or credentials. User passwords are set with
`passwd`, and SSH keys and fingerprint data live outside the repository.
