# remote-builder.nix — offload x86_64-linux builds to the downstairs Thelio
# (128-core Threadripper, host "nixos") AND use it as a personal binary cache.
#
# WIRE IT UP:  add  ./remote-builder.nix  to your imports in configuration.nix, then
#   sudo nixos-rebuild switch   (or your ixnay reify)
# Tower side pairs with system76_thelio_nixos/binary-cache.nix (enables nix-serve).
#
# Drafted 2026-06-13. Inert until imported.
{ config, lib, pkgs, ... }:

{
  ###### distributed builds: send compiles to the 128-core tower ######
  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      hostName = "192.168.7.193";                 # tower's wired DHCP reservation
      sshUser = "pmarreck";                        # in wheel -> trusted on the tower
      sshKey = "/home/pmarreck/.ssh/id_ed25519";   # already in tower authorized_keys; root-readable
      protocol = "ssh-ng";
      systems = [ "x86_64-linux" ];                # same arch as laptop -> can build everything
      maxJobs = 16;                                # parallel derivations on the tower
      speedFactor = 20;                            # >> laptop, so nix prefers it
      supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
    }
  ];
  # let the tower pull deps from its own substituters instead of the laptop uploading them
  nix.settings.builders-use-substitutes = true;

  ###### personal binary cache: download what the tower already built ######
  # ENABLE ONLY AFTER nix-serve is running on the tower (see binary-cache.nix snippet),
  # otherwise every nix op pays a connect-timeout to a dead substituter.
  # The remote BUILDER above needs none of this and no tower-config change at all.
  # nix.settings.substituters = lib.mkAfter [ "http://192.168.7.193:5000" ];
  # nix.settings.trusted-public-keys = lib.mkAfter [
  #   "thelio-1:m//JytIzv3CZgtLYLQIPDpkMA7DKYxGof01zM8+Ljdk="
  # ];

  ###### so the nix-daemon (root) verifies the tower host key non-interactively ######
  programs.ssh.knownHosts."tower-thelio" = {
    hostNames = [ "192.168.7.193" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBPxuSyHdDAzPvQiUNxwck7gk6OI3wIA/fzVSVT/j+9Z";
  };
}
