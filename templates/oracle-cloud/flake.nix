{
  description = "OCI Always-Free A1.Flex NixOS — harness daily-progress bot host";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, home-manager, ... }: {
    nixosConfigurations.harness-daily-progress = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        disko.nixosModules.disko
        home-manager.nixosModules.home-manager
        ./nixos/hardware-configuration.nix
        ./nixos/disko.nix
        ./nixos/configuration.nix
      ];
    };
  };
}
