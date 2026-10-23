{ pkgs, llmsendWriteNote ? null }:
let
  provisionBroker = import ./provision-package.nix { inherit pkgs; };
  notificationSource = pkgs.runCommand "mechatron-notification-source" {} ''
    mkdir -p "$out/notifications"
    cp ${../notifications}/*.lua "$out/notifications/"
  '';
  notifications = pkgs.writeShellApplication {
    name = "mechatron-prime-notifications";
    runtimeInputs = [
      pkgs.coreutils pkgs.git pkgs.sqlite
      (pkgs.luajit.withPackages (ps: [ ps.cjson ]))
      (if llmsendWriteNote == null then
        throw "Notification packaging requires the pinned LLMsend writeNote package"
      else llmsendWriteNote)
    ];
    text = ''exec luajit ${notificationSource}/notifications/main.lua "$@"'';
  };
  mechatronProvision = pkgs.writeShellApplication {
    name = "provision-mechatron-webhooks";
    # policy.bash is concatenated whole. Provision calls the retry helpers.
    # The badge and queue helpers in that file are for the worker, and
    # ShellCheck cannot see that split from this composed script.
    excludeShellChecks = [ "SC2329" ];
    runtimeInputs = [ pkgs.coreutils pkgs.gh pkgs.jq ];
    text = builtins.readFile ../scripts/policy.bash
      + "\n"
      + builtins.readFile ../scripts/provision-mechatron-webhooks;
  };
  mechatronCi = pkgs.writeShellApplication {
    name = "mechatron-ci";
    runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.git pkgs.jq mechatronProvision ];
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
  inherit mechatronCi mechatronControl worker notifications provisionBroker;
}
