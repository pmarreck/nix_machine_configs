{ pkgs }:
let
  mechatronProvision = pkgs.writeShellApplication {
    name = "provision-mechatron-webhooks";
    excludeShellChecks = [ "SC2329" ];
    runtimeInputs = [ pkgs.coreutils pkgs.gh pkgs.jq ];
    text = builtins.readFile ../scripts/policy.bash + "\n"
      + builtins.readFile ../scripts/provision-mechatron-webhooks;
  };
  provisionSource = pkgs.runCommand "mechatron-provision-source" {} ''
    mkdir -p "$out/provision" "$out/ops"
    cp ${../provision}/*.lua "$out/provision/"
    cp ${../ops/http.lua} "$out/ops/http.lua"
  '';
  provisionRunner = pkgs.writeShellApplication {
    name = "mechatron-prime-provision-run";
    runtimeInputs = [ pkgs.coreutils pkgs.gh pkgs.jq mechatronProvision ];
    text = ''
      export MECHATRON_PROVISION_HELPER="${mechatronProvision}/bin/provision-mechatron-webhooks"
    '' + builtins.readFile ../scripts/provision-broker-run;
  };
  provisionBroker = pkgs.writeShellApplication {
    name = "mechatron-prime-provision";
    runtimeInputs = [ pkgs.coreutils (pkgs.luajit.withPackages (ps: [ ps.cjson ps.luasocket ])) ];
    text = ''
      export LUA_PATH="${provisionSource}/?.lua;;"
      export MECHATRON_PROVISION_RUNNER="${provisionRunner}/bin/mechatron-prime-provision-run"
      exec luajit ${provisionSource}/provision/main.lua
    '';
  };
in provisionBroker
