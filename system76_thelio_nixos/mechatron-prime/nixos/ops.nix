# Mechatron Prime — tailnet-only host operations console and local maintenance timers.
{ pkgs, ... }:
let
  luaEnv = pkgs.luajit.withPackages (ps: with ps; [ cjson luasocket ]);
  # Keep the complete runtime tree as an explicit derivation input. This makes
  # source changes observable even when the Nix evaluator reuses module parses.
  opsInput = builtins.path {
    path = ../ops;
    name = "mechatron-prime-ops-input";
  };
  opsSource = pkgs.runCommand "mechatron-prime-ops-source" { } ''
    mkdir -p "$out/ops"
    cp -R ${opsInput}/. "$out/ops/"
  '';
  opsServer = pkgs.writeShellApplication {
    name = "mechatron-prime-ops";
    runtimeInputs = [
      luaEnv
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.gawk
      pkgs.iproute2
      pkgs.procps
      pkgs.sqlite
      pkgs.systemd
      pkgs.util-linux
      pkgs.zfs
    ];
    text = ''
      export LUA_PATH="${opsSource}/?.lua;;"
      exec ${luaEnv}/bin/luajit ${opsSource}/ops/server.lua
    '';
  };
in
{
  systemd.services.mechatron-prime-ops = {
    description = "Mechatron Prime tailnet-only operations console";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "network-online.target" ];
    environment = {
      MECHATRON_OPS_ADDRESS = "127.0.0.1";
      MECHATRON_OPS_PORT = "9002";
      MECHATRON_OPS_ADMIN_LOGIN = "lumbergh@gmail.com";
      MECHATRON_OPS_ORIGIN = "https://thelio-nixos.tail66c90.ts.net:8444";
    };
    serviceConfig = {
      ExecStart = "${opsServer}/bin/mechatron-prime-ops";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = "read-only";
      ReadWritePaths = [ "/home/pmarreck/.codex" "/var/lib/mechatron-prime" ];
      ProtectSystem = "strict";
      RestrictAddressFamilies = [ "AF_INET" "AF_UNIX" ];
      RestrictSUIDSGID = true;
    };
  };

  # Port 443 remains public Funnel for badges/webhooks. A distinct Serve port
  # keeps the operations console accessible only from Peter's tailnet.
  systemd.services.mechatron-prime-ops-route = {
    description = "Publish Mechatron Prime operations privately through Tailscale Serve";
    wantedBy = [ "multi-user.target" ];
    after = [ "tailscaled.service" "mechatron-prime-ops.service" ];
    requires = [ "tailscaled.service" "mechatron-prime-ops.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --yes --https=8444 --set-path=/ops http://127.0.0.1:9002/ops";
      ExecStop = "${pkgs.tailscale}/bin/tailscale serve --yes --https=8444 --set-path=/ops off";
      RemainAfterExit = true;
      # tailscaled can report active before its local control socket reaches
      # Running; retry its transient NoState response instead of leaving a
      # stale persisted Serve route after boot.
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.user.services.fsearch-update = {
    description = "Rebuild Peter's FSearch database";
    unitConfig.ConditionUser = "pmarreck";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/home/pmarreck/Code/fsearch/result/bin/fsearch --update-database";
    };
  };

  systemd.user.timers.fsearch-update = {
    description = "Rebuild Peter's FSearch database nightly";
    wantedBy = [ "timers.target" ];
    unitConfig.ConditionUser = "pmarreck";
    timerConfig = {
      OnCalendar = "*-*-* 03:30:00";
      Persistent = true;
      Unit = "fsearch-update.service";
    };
  };
}
