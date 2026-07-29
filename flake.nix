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

    # Peter's Ollama fork enables parallel embedding runners.
    #
    # Referenced by URL, NOT as a `path:` input. It was previously
    # `path:/home/pmarreck/Code/ollama` — "intentionally local until its upstream
    # push" — but that push did not happen, so every OTHER machine's
    # `nix flake update` died with "path does not exist" and no CI could evaluate
    # this flake at all. bin/check-flake-portability now refuses that shape.
    # To adopt a later fork revision: `nix flake update ollama`, then
    # `ixnay reify no-upgrade` when it is safe to restart the daemon.
    ollama = {
      url = "github:pmarreck/ollama/main"; # main, not yolo: this is a FORK of ollama/ollama, whose upstream default is main — and yolo was 13 commits stale, missing the CUDA toolkit pin (edab7d2) that this build requires
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Himalaya — CLI email client (pimalaya). Wanted for its 2.0 release, which
    # nixpkgs does not yet carry (nixpkgs is still 1.2.0 as of 2026-07-29), so
    # the package MUST come from upstream's flake rather than `pkgs.himalaya`.
    # Reason for adoption: the built-in Gmail tooling binds a single account;
    # Himalaya manages both (lumbergh@gmail.com + peter@marreck.com) and gives a
    # composable CLI mail core.
    #
    # Deliberately does NOT `follows = nixpkgs`, unlike ollama above. Himalaya is
    # a fenix-based Rust build with its own pinned nixpkgs; forcing our nixpkgs
    # onto a fenix toolchain is how these builds break, and leaving it pinned
    # means the system build reuses the exact derivation `nix run
    # github:pimalaya/himalaya` already produced instead of recompiling. Passes
    # bin/check-flake-portability (github: input, not a path:/file:// one).
    himalaya.url = "github:pimalaya/himalaya";
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
