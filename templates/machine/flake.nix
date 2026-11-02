# This machine, running NIHIL. The installer wrote it; it's yours to change.
#
#   settings.json               who uses it, language, keyboard, screens, Nilo
#   hardware-configuration.nix  disks and drivers (nixos-generate-config)
#   local.nix                   anything else for this machine
#   home.nix                    anything else for its user (Home Manager)
#
# nihil rebuild applies it; nihil update brings the latest NIHIL.

{
	description = "A machine running NIHIL";

	inputs.nihil.url = "github:poligle/Nihil-Shell";

	# Named after the computer (settings.json's host), as NixOS expects.
	outputs = { nihil, ... }:
	let
		settings = builtins.fromJSON (builtins.readFile ./settings.json);
	in
	{
		nixosConfigurations.${settings.host.name} = nihil.lib.mkSystem
		{
			inherit settings;
			modules = [ ./hardware-configuration.nix ./local.nix ];
			home = [ ./home.nix ];
		};
	};
}
