{
  description = "Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager }: let
	linux-config = home-manager.lib.homeManagerConfiguration {
		pkgs = import nixpkgs { system = "x86_64-linux"; };
		modules = [
			./home.nix
		];
	};
in	
{
	nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
		modules = [ 
			./configuration.nix
          		home-manager.nixosModules.home-manager
			{
				home-manager.useGlobalPkgs = true;
				home-manager.useUserPackages = true;
				home-manager.users.frerom = ./home.nix;
			}
		];
	};
	defaultPackage.x86_64-linux = linux-config.activationPackage;
  };
}
