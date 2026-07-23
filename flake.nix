{
  description = "Peter's NixOS systems";

  inputs = {
    # Thelio's base system and every host's explicit `unstable` scope. `nix flake
    # update` advances it without forcing Framework's desktop base to compile.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The `stable` scope — follows the release-26.05 branch so `nix flake update`
    # (i.e. `ixnay reify --upgrade`) rolls it. Supersedes the old in-config tarball
    # pin (rev 721be2608f425037939026ef94839680fe67b9a4). Swap to a rev pin here for
    # full determinism if a rolling stable ever proves too lively.
    nixpkgs-2605.url = "github:NixOS/nixpkgs/release-26.05";

    # A narrow fallback for packages whose current release build has not reached
    # cache.nixos.org yet. Keep Framework's base on 26.05.
    nixpkgs-2511.url = "github:NixOS/nixpkgs/release-25.11";

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Peter's local Ollama fork enables parallel embedding runners. It is a
    # locked path input because the desired commit is intentionally local until
    # its upstream push; flake.lock records the exact source snapshot. To adopt
    # a later local fork revision: `cd /etc/nixos && nix flake update ollama`,
    # then `ixnay reify --no-update` when it is safe to restart the daemon.
    ollama = {
      url = "path:/home/pmarreck/Code/ollama";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-2605, nixpkgs-2511, nixos-hardware, ... }@inputs:
    let
      system = "x86_64-linux";
      mkHost = pkgsInput: module: pkgsInput.lib.nixosSystem {
        inherit system;

        # `inputs` + `system` reach configuration.nix via specialArgs. Host modules
        # build their own extra nixpkgs scopes from these flake inputs so host-specific
        # nixpkgs config stays in the host module rather than being duplicated here.
        specialArgs = { inherit inputs system; };

        modules = [ module ];
      };
    in {
      nixosConfigurations = {
        thelio-nixos = mkHost nixpkgs ./system76_thelio_nixos/configuration.nix;
        # Framework uses the latest released package set for cache hits; the
        # module still receives `inputs.nixpkgs` as its explicit unstable scope.
        framework-nixos = mkHost nixpkgs-2605 ./framework-nixos/configuration.nix;
      };
    };
}
