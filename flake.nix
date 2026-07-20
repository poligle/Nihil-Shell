# flake.nix by poligle

{
	description = "NixOS Config for poligle@thinkpad";
	inputs = {
		nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
		
		home-manager = {
			url = "github:nix-community/home-manager/release-26.05";
			inputs.nixpkgs.follows = "nixpkgs";
		};
	};
	outputs = { self, nixpkgs, home-manager, ... }:
	{
		nixosConfigurations.thinkpad = nixpkgs.lib.nixosSystem {
			system = "x86_64-linux";
			modules = [
				./configuration.nix
				
				home-manager.nixosModules.home-manager
				{
					home-manager.useGlobalPkgs = true;
					home-manager.useUserPackages = true;
					home-manager.users.poligle = import ./home.nix;
				}
			];
		};
	};
}
