# nix_machine_configs

The collection of my Nix/NixOS machine configurations.

When setting this up on a new machine, please do the following:
- Back up the existing `/etc/nixos`: `sudo cp -R /etc/nixos /etc/nixos.bak`
- `git clone` this repo somewhere and then `cp -R` to `/etc/nixos`
- `cd /etc/nixos` and then `mkdir <name of the new machine>`
- Add a `configuration.nix`, a `hardware-configuration.nix` and optionally a `zfs.nix` to that directory (or copy from the backup of `/etc/nixos` in `/etc/nixos.bak`)
- Symlink (`ln -s`) those into `/etc/nixos`: `cd /etc/nixos; ln -s <new_machine_name>/*.nix`
