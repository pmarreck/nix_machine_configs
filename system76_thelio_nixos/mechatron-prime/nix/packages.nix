{ pkgs }:
let
  mechatronCi = pkgs.writeShellApplication {
    name = "mechatron-ci";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.jq ];
    text = builtins.readFile ../scripts/mechatron-ci;
  };
  mechatronControl = pkgs.writeShellApplication {
    name = "mechatron-prime-control";
    runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.systemd pkgs.util-linux ];
    text = builtins.readFile ../scripts/control_lib.bash
      + "\n"
      + builtins.readFile ../scripts/mechatron-prime-control;
  };
  worker = pkgs.writeShellApplication {
    name = "mechatron-prime-worker";
    # Signal traps dispatch these helpers by name, which ShellCheck cannot
    # recognize as direct invocations in the composed package script.
    excludeShellChecks = [ "SC2329" ];
    runtimeInputs = [
      pkgs.attic-client
      pkgs.coreutils
      pkgs.jq
      pkgs.nix
      pkgs.sqlite
      pkgs.util-linux
    ];
    text = builtins.readFile ../scripts/policy.bash
      + "\n"
      + builtins.readFile ../scripts/status_store.bash
      + "\n"
      + builtins.readFile ../scripts/control_lib.bash
      + "\n"
      + builtins.readFile ../scripts/worker.bash;
  };
in
{
  inherit mechatronCi mechatronControl worker;
}
