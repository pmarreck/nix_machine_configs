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

    # Keep the WSL integration on the same release series as the NixOS host.
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-2605";
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

  outputs = { self, nixpkgs, nixpkgs-2605, nixpkgs-2511, nixos-hardware, nixos-wsl, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      codexApp = pkgs.callPackage ./packages/codex-app.nix { };
      tode = pkgs.callPackage ./packages/tode.nix { };
      codexAppSmoke = pkgs.runCommand "codex-app-smoke-${codexApp.version}" {
        nativeBuildInputs = [ codexApp ];
      } ''
        export HOME=/tmp/codex-app-smoke
        export XDG_CONFIG_HOME="$HOME/config"
        export XDG_CACHE_HOME="$HOME/cache"
        mkdir -p "$HOME" "$out"
        cd "$HOME"
        actual="$(chatgpt --version)"
        if [ "$actual" != "${codexApp.version}" ]; then
          printf 'expected Codex app %s, got %s\n' \
            "${codexApp.version}" "$actual" >&2
          exit 1
        fi
        printf '%s\n' "$actual" > "$out/version"
      '';
      todeSmoke = pkgs.runCommand "tode-smoke-${tode.version}" {
        nativeBuildInputs = [ tode ];
      } ''
        export HOME=/tmp/tode-smoke
        export XDG_CONFIG_HOME="$HOME/config"
        export XDG_CACHE_HOME="$HOME/cache"
        export XDG_DATA_HOME="$HOME/data"
        export XDG_STATE_HOME="$HOME/state"
        mkdir -p "$HOME" "$out"
        cd "$HOME"
        actual="$(tode --version)"
        case "$actual" in
          v${tode.version}|${tode.version}) ;;
          *)
            printf 'expected Terminal Code %s, got %s\n' \
              "${tode.version}" "$actual" >&2
            exit 1
            ;;
        esac
        printf '%s\n' "$actual" > "$out/version"
      '';
      mkHost = pkgsInput: module: pkgsInput.lib.nixosSystem {
        inherit system;

        # `inputs` + `system` reach configuration.nix via specialArgs. Host modules
        # build their own extra nixpkgs scopes from these flake inputs so host-specific
        # nixpkgs config stays in the host module rather than being duplicated here.
        specialArgs = { inherit inputs system codexApp tode; };

        modules = [ module ];
      };
    in {
      packages.${system} = {
        codex-app = codexApp;
        inherit tode;
      };
      checks.${system} = {
        codex-app = codexAppSmoke;
        tode = todeSmoke;
      };

      nixosConfigurations = {
        thelio-nixos = mkHost nixpkgs ./system76_thelio_nixos/configuration.nix;
        # Framework uses the latest released package set for cache hits; the
        # module still receives `inputs.nixpkgs` as its explicit unstable scope.
        framework-nixos = mkHost nixpkgs-2605 ./framework-nixos/configuration.nix;
        tiki-wsl-nixos = nixpkgs-2605.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs system; };
          modules = [
            nixos-wsl.nixosModules.default
            ./tiki-wsl-nixos/configuration.nix
          ];
        };
      };
    };
}
