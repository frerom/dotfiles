{
  description = "Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, home-manager }:
  let
    system = "x86_64-linux";

    mkHost = hostName: nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./hosts/${hostName}/configuration.nix

        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.frerom = ./home.nix;
        }
      ];
    };

    linux-config = home-manager.lib.homeManagerConfiguration {
      pkgs = import nixpkgs { inherit system; };
      modules = [ ./home.nix ];
    };
  in
  {
    nixosConfigurations = {
      office   = mkHost "office";
      thinkpad = mkHost "thinkpad";
    };

    defaultPackage.${system} = linux-config.activationPackage;
  };
}
