# Unattended Dune: Awakening world for the login that owns the checkout.
# Spec: dune_awakening_server libexec/dune-units. These are user units so
# `dune-awakening start` can create the map server's memory-capped user
# scope. ConditionUser keeps any other login from starting that checkout.
# Linger is what makes the user manager, and therefore the world, start at
# boot without an interactive session.
{ pkgs, lib, ... }:
let
  duneRoot = "/home/pmarreck/Code/dune_awakening_server";
  world = "${duneRoot}/bin/dune-awakening";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  path = lib.concatStringsSep ":" (lib.unique [
    "${pkgs.luajit}/bin"
    "${pkgs.nix}/bin"
    "/run/current-system/sw/bin"
    "/usr/bin"
    "/bin"
  ]);
  onlyPeter = {
    ConditionUser = "pmarreck";
  };
in
{
  users.users.pmarreck.linger = true;

  systemd.user.services.dune-world = {
    description = "Dune: Awakening world (native, ${duneRoot})";
    wantedBy = [ "default.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig = onlyPeter;
    environment.PATH = path;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${world} start";
      ExecStop = "${world} stop --force";
      TimeoutStartSec = "20min";
      TimeoutStopSec = "6min";
    };
  };

  systemd.user.services.dune-world-heal = {
    description = "Restart any stopped Dune world component while the world is meant to be up";
    unitConfig = onlyPeter;
    environment.PATH = path;
    serviceConfig = {
      Type = "oneshot";
      ExecCondition = "${systemctl} --user is-active --quiet dune-world.service";
      ExecStart = "${world} start --no-warn";
      KillMode = "process";
      TimeoutStartSec = "20min";
    };
  };

  systemd.user.timers.dune-world-heal = {
    description = "Check the Dune world every 5 minutes";
    wantedBy = [ "timers.target" ];
    unitConfig = onlyPeter;
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "5min";
      Unit = "dune-world-heal.service";
    };
  };

  systemd.user.services.dune-backup = {
    description = "Back up the Dune world database and operator config";
    unitConfig = onlyPeter;
    environment.PATH = path;
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = duneRoot;
      ExecStart = "${world} backup create --label scheduled";
      ExecStartPost = "${world} backup prune";
    };
  };

  systemd.user.timers.dune-backup = {
    description = "Daily Dune world backup";
    wantedBy = [ "timers.target" ];
    unitConfig = onlyPeter;
    timerConfig = {
      OnCalendar = "*-*-* 04:30:00";
      Persistent = true;
      Unit = "dune-backup.service";
    };
  };

  systemd.user.services.dune-backup-verify = {
    description = "Restore drill: restore the newest Dune backup into a scratch database";
    unitConfig = onlyPeter;
    environment.PATH = path;
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = duneRoot;
      ExecStart = "${world} backup verify latest";
    };
  };

  systemd.user.timers.dune-backup-verify = {
    description = "Weekly Dune backup restore drill";
    wantedBy = [ "timers.target" ];
    unitConfig = onlyPeter;
    timerConfig = {
      OnCalendar = "Sun *-*-* 05:15:00";
      Persistent = true;
      Unit = "dune-backup-verify.service";
    };
  };

  systemd.user.services.dune-update-check = {
    description = "Check whether Steam has a newer Dune self-hosted server build";
    unitConfig = onlyPeter;
    environment.PATH = path;
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = duneRoot;
      ExecStart = "${world} update check --json";
      SuccessExitStatus = [ "1" ];
    };
  };

  systemd.user.timers.dune-update-check = {
    description = "Daily Dune server update check";
    wantedBy = [ "timers.target" ];
    unitConfig = onlyPeter;
    timerConfig = {
      OnCalendar = "*-*-* 06:00:00";
      Persistent = true;
      Unit = "dune-update-check.service";
    };
  };
}
