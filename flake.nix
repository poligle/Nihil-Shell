# flake.nix by poligle

{
	description = "NixOS Config for poligle@thinkpad";

	inputs = 
	{
		nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

		home-manager = 
		{
			url = "github:nix-community/home-manager/release-26.05";
			inputs.nixpkgs.follows = "nixpkgs";
		};

        stylix = 
		{
			url = "github:nix-community/stylix/release-26.05";
			inputs.nixpkgs.follows = "nixpkgs";
		};

        zen-browser = {
            url = "github:0xc000022070/zen-browser-flake";
            inputs = {
                home-manager.follows = "home-manager";
            };
        };
	};
	outputs = inputs@{ self, nixpkgs, home-manager, stylix, zen-browser , ... }:
	{
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
	};
}
