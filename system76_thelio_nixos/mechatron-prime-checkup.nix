{ config, inputs, pkgs, lib, ... }:
let
  operator = config.services.unix-mail-redux.owner;
  home = config.users.users.${operator}.home;
  package = pkgs.callPackage ./mechatron-prime-checkup/nix/watch-package.nix {
    llmsendSource = inputs.llmsend_reminders;
  };
in {
  imports = [
    (import ./mechatron-prime-checkup/nixos/watch.nix {
      inherit package operator home lib;
      inbox = "${home}/Code/mechatron-prime/inbox";
    })
  ];
  environment.systemPackages = [ package ];
}
