# Fleet upkeep belongs to the user login, but the timer's existence belongs to
# this machine's declarative configuration. The executable stays in dotfiles.
{ pkgs, lib, ... }:
let
  lua = pkgs.luajit.withPackages (ps: [ ps.lua-cjson ]);
  runtimePath = lib.concatStringsSep ":" [
    "/home/pmarreck/bin"
    "/home/pmarreck/dotfiles/bin"
    (lib.makeBinPath [
      lua pkgs.b3sum pkgs.coreutils pkgs.git pkgs.openssh pkgs.findutils
      pkgs.gh pkgs.curl pkgs.tokei pkgs.jq pkgs.gnugrep pkgs.gawk
    ])
    "/run/current-system/sw/bin"
    "/usr/bin"
    "/bin"
  ];
in
{
  systemd.user.services.fleet-status = {
    description = "Maintain Git remotes and publish Peter's fleet report";
    unitConfig.ConditionUser = "pmarreck";
    environment.PATH = lib.mkForce runtimePath;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/home/pmarreck/dotfiles/bin/repo-maintenance";
      Nice = 10;
      IOSchedulingClass = "idle";
      TimeoutStartSec = "4h";
    };
  };

  systemd.user.timers.fleet-status = {
    description = "Run repository maintenance at night";
    wantedBy = [ "timers.target" ];
    unitConfig.ConditionUser = "pmarreck";
    timerConfig = {
      OnCalendar = "*-*-* 03:15:00";
      RandomizedDelaySec = "15m";
      Persistent = true;
      Unit = "fleet-status.service";
    };
  };
}
