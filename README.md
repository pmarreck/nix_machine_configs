# nix_machine_configs

The collection of my Nix/NixOS machine configurations.

When setting this up on a new NixOS machine, please do the following:
- make git available on the machine ephemerally : `nix-shell -p git`
- `git clone` this repo into $HOME : `git clone https://github.com/pmarreck/nix_machine_configs ~/nixos-configs`
- Run `install.sh` in this repo : `./install.sh`

Done!
