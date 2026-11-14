# flake.nix by poligle

{
	description = "NIHIL: a monochrome, dot-matrix desktop for NixOS";

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

		zen-browser =
		{
			url = "github:0xc000022070/zen-browser-flake";
			inputs.nixpkgs.follows = "nixpkgs";
			inputs.home-manager.follows = "home-manager";
		};
	};
	outputs = inputs@{ self, nixpkgs, home-manager, stylix, zen-browser, ... }:
	let
		system = "x86_64-linux";

		date = self.lastModifiedDate or "19700101000000";
		at = start: length: builtins.substring start length date;
		revision = "${self.shortRev or self.dirtyShortRev or "local"} (${at 0 4}-${at 4 2}-${at 6 2} ${at 8 2}:${at 10 2})";
	in
	{
		nixosModules.default = { config, ... }:
		{
			imports =
			[
				stylix.nixosModules.stylix
				home-manager.nixosModules.home-manager
				./modules
			];

			home-manager =
			{
				useGlobalPkgs = true;
				useUserPackages = true;
				backupFileExtension = "hm-backup";
				extraSpecialArgs = { inherit inputs; };
				users.${config.nihil.user.name}.imports = [ ./home.nix ] ++ config.nihil.home;
			};
		};

		lib.mkSystem = { settings ? { }, modules ? [ ], home ? [ ] }: nixpkgs.lib.nixosSystem
		{
			inherit system;
			modules = [ self.nixosModules.default { nihil = { inherit settings home revision; }; } ] ++ modules;
		};

		nixosConfigurations =
		{
			installer = nixpkgs.lib.nixosSystem
			{
				inherit system;
				specialArgs = { nihil = self; };
				modules = [ ./installer/iso.nix ];
			};

			example = self.lib.mkSystem
			{
				settings = builtins.fromJSON (builtins.readFile ./templates/machine/settings.json);
				modules = [ ./templates/example/hardware-configuration.nix ./templates/machine/local.nix ];
				home = [ ./templates/machine/home.nix ];
			};
		};

		packages.${system}.iso = self.nixosConfigurations.installer.config.system.build.isoImage;

		templates.default =
		{
			path = ./templates/machine;
			description = "A machine running NIHIL: settings.json, local.nix and home.nix";
		};
	};
}
