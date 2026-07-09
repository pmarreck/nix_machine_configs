{
  description = "Peter's NixOS systems";

  inputs = {
    # Base system + the `unstable` scope (rolling nixos-unstable — matches the
    # current base; `nix flake update` advances it).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The `stable` scope — follows the release-26.05 branch so `nix flake update`
    # (i.e. `ixnay reify --upgrade`) rolls it. Supersedes the old in-config tarball
    # pin (rev 721be2608f425037939026ef94839680fe67b9a4). Swap to a rev pin here for
    # full determinism if a rolling stable ever proves too lively.
    nixpkgs-2605.url = "github:NixOS/nixpkgs/release-26.05";

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-2605, nixos-hardware, ... }@inputs:
    let
      system = "x86_64-linux";
      mkHost = module: nixpkgs.lib.nixosSystem {
        inherit system;

        # `inputs` + `system` reach configuration.nix via specialArgs. Host modules
        # build their own extra nixpkgs scopes from these flake inputs so host-specific
        # nixpkgs config stays in the host module rather than being duplicated here.
        specialArgs = { inherit inputs system; };

        modules = [ module ];
      };
    in {
      nixosConfigurations = {
        nixos = mkHost ./system76_thelio_nixos/configuration.nix;
        framework-nixos = mkHost ./framework-nixos/configuration.nix;
      };
    };
}
