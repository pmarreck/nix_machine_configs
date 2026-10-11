{ lib, pkgs, ... }:
let
  source = ./mechatron-prime-provision;
  cli = pkgs.writeShellApplication {
    name = "mechatron-ci";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.git pkgs.jq ];
    text = builtins.readFile (source + "/scripts/mechatron-ci");
  };
in {
  imports = [ (source + "/nixos/provision.nix") ];
  services.mechatronPrimeProvision = {
    enable = true;
    operator = "pmarreck";
    endpoint = "https://thelio-nixos.tail66c90.ts.net/hooks/github";
  };
  environment.systemPackages = [ (lib.hiPrio cli) ];
}
