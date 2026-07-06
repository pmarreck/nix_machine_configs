{
  description = "Peter's thelio NixOS system";

  inputs = {
    # Base system + the `unstable` scope (rolling nixos-unstable — matches the
    # current base; `nix flake update` advances it).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The `stable` scope — follows the release-26.05 branch so `nix flake update`
    # (i.e. `ixnay reify --upgrade`) rolls it. Supersedes the old in-config tarball
    # pin (rev 721be2608f425037939026ef94839680fe67b9a4). Swap to a rev pin here for
    # full determinism if a rolling stable ever proves too lively.
    nixpkgs-2605.url = "github:NixOS/nixpkgs/release-26.05";
  };

  outputs = { self, nixpkgs, nixpkgs-2605, ... }@inputs:
    let
      system = "x86_64-linux";
    in {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        inherit system;

        # `inputs` + `system` reach configuration.nix via specialArgs. The host module
        # builds its own base `pkgs` from `nixpkgs.config`/`nixpkgs.overlays` (so allowUnfree,
        # permittedInsecurePackages and both overlays keep working) and instantiates the
        # `unstable`/`stable` scopes itself from these inputs — passing `system` explicitly
        # because pure flake eval has no `builtins.currentSystem` fallback. All host-specific
        # nixpkgs config stays in the host module rather than being duplicated in this flake.
        specialArgs = { inherit inputs system; };

        modules = [ ./system76_thelio_nixos/configuration.nix ];
      };
    };
}
