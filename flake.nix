{
	description = "NixOS Config for poligle@thinkpad";
	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
	};
	outputs = { self, nixpkgs, ... }:
	{
		nixosConfigurations.thinkpad = nixpkgs.lib.nixosSystem {
			system = "x86_64-linux";
			modules = [
				./configuration.nix
			];
		};
	};
}
