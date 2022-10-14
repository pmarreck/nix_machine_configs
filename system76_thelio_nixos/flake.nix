{
  inputs = {
    unstable.url = github:NixOS/nixpkgs-channels/nixos-unstable;
    stable.url = github:NixOS/nixpkgs-channels/nixos-22.05;
    trunk.url = "github:NixOS/nixpkgs";
    nixpkgs.url = github:NixOS/nixpkgs-channels/nixos-unstable;
    home-manager.url = github:nix-community/home-manager;
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nixos-hardware.url = github:NixOS/nixos-hardware/master;
  };
  
  outputs = inputs@{ self, nixpkgs, home-manager, nixos-hardware, ... }: {
    overlays = {
      # Inject 'unstable', 'stable' and 'trunk' into the overridden package set, so that
      # the following overlays may access them (along with any system configs
      # that wish to do so).
      pkg-sets = (
        final: prev: {
          unstable = import inputs.unstable { system = final.system; };
          stable = import inputs.stable { system = final.system; };
          trunk = import inputs.trunk { system = final.system; };
        }
      );
    };
    # "nixos" below is my hostname
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = inputs;
      modules = [
        nixos-hardware.nixosModules.system76
        home-manager.nixosModules.home-manager
        ./configuration.nix
      ];
    };
  };
}
