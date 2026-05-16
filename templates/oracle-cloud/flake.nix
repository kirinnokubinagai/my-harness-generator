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
    # numtide/llm-agents.nix — packages claude-code, codex, cli-proxy-api,
    # hermes-agent, openclaw (aarch64-linux, daily auto-updated, binary cache).
    # Deliberately NOT `inputs.nixpkgs.follows = "nixpkgs"`: keeping its own
    # pinned nixpkgs is what makes the numtide binary cache hit (overlays.default
    # serves prebuilt packages.${system} as-is). Following our nixpkgs would
    # force a full from-source rebuild of every agent on every deploy.
    llm-agents.url = "github:numtide/llm-agents.nix";
  };

  outputs = { self, nixpkgs, disko, home-manager, llm-agents, ... }: {
    nixosConfigurations.harness-daily-progress = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        disko.nixosModules.disko
        home-manager.nixosModules.home-manager
        # Exposes pkgs.llm-agents.<name> (claude-code, codex, cli-proxy-api,
        # hermes-agent, openclaw) built against numtide's pinned nixpkgs so
        # the binary cache hits regardless of our nixpkgs revision.
        { nixpkgs.overlays = [ llm-agents.overlays.default ]; }
        ./nixos/hardware-configuration.nix
        ./nixos/disko.nix
        ./nixos/configuration.nix
      ];
    };
  };
}
