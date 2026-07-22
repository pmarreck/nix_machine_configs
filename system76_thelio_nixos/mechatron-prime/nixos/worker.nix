# Mechatron Prime — sequential owner-wide multi-repository Nix worker.
{ lib, pkgs, ... }:
let
  runtime = import ../nix/packages.nix { inherit pkgs; };
  legacyTargets = import ./legacy-targets.nix;
  legacyTargetDirectory = "/etc/mechatron-prime/legacy-targets";
  badgeDirectory = "/var/lib/mechatron-prime-public/badges";
  legacyTargetSeedRules = lib.mapAttrsToList
    (repo: targets:
      let
        repoName = lib.last (lib.splitString "/" repo);
        seed = pkgs.writeText "mechatron-prime-${repoName}-legacy-targets"
          (lib.concatStringsSep "\n" targets + "\n");
      in
        "L+ ${legacyTargetDirectory}/${repoName}.targets - - - - ${seed}")
    legacyTargets;
  initialControl = pkgs.writeText "mechatron-prime-initial-control.json"
    ''{"state":"running","changed_at":"activation"}'';
in
{
  environment.systemPackages = [ runtime.mechatronCi runtime.mechatronControl ];

  systemd.tmpfiles.rules = [
    "d /etc/mechatron-prime 0710 root mechatron-prime - -"
    "d ${legacyTargetDirectory} 0750 root mechatron-prime - -"
    "z /etc/nix/netrc 0640 root mechatron-prime - -"
    "d /var/lib/mechatron-prime 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/.cache 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/.config 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/.config/attic 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/batches 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/logs 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/queue 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/work 0750 mechatron-prime mechatron-prime - -"
    "f /var/lib/mechatron-prime/queue/builds.ndjson 0640 mechatron-prime mechatron-prime - -"
    "f /var/lib/mechatron-prime/results.ndjson 0640 mechatron-prime mechatron-prime - -"
    "f /var/lib/mechatron-prime/results.sqlite3 0640 mechatron-prime mechatron-prime - -"
    "f /var/lib/mechatron-prime/current.json 0640 mechatron-prime mechatron-prime - -"
    "C /var/lib/mechatron-prime/control.json 0640 root mechatron-prime - ${initialControl}"
    "z /var/lib/mechatron-prime/control.json 0640 root mechatron-prime - -"
  ] ++ legacyTargetSeedRules;

  systemd.services.mechatron-prime-worker = {
    description = "Mechatron Prime sequential multi-repository build worker";
    after = [ "network-online.target" "atticd.service" "nix-daemon.service" ];
    wants = [ "network-online.target" "atticd.service" ];

    environment = {
      HOME = "/var/lib/mechatron-prime";
      XDG_CACHE_HOME = "/var/lib/mechatron-prime/.cache";
      XDG_CONFIG_HOME = "/var/lib/mechatron-prime/.config";
      MECHATRON_STATE_DIR = "/var/lib/mechatron-prime";
      MECHATRON_GITHUB_OWNER = "pmarreck";
      MECHATRON_LEGACY_TARGETS_DIR = legacyTargetDirectory;
      MECHATRON_BADGE_DIR = badgeDirectory;
      MECHATRON_BUILD_TIMEOUT_SECONDS = "7200";
      # CI must remain independent of Garnix even while the global host
      # configuration still lists its soon-to-disappear substituter.
      MECHATRON_SUBSTITUTERS = "http://100.96.171.61:8080/fleet https://cache.nixos.org/";
      # Keep fleet CI honest while native Zig flakes are audited for explicit
      # baseline CPUs. The local Nix store still reuses successful builds.
      MECHATRON_CACHE_PUSH = "false";
    };

    serviceConfig = {
      Type = "oneshot";
      User = "mechatron-prime";
      Group = "mechatron-prime";
      WorkingDirectory = "/var/lib/mechatron-prime";
      ExecStart = "${runtime.worker}/bin/mechatron-prime-worker";
      TimeoutStartSec = "6h";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadOnlyPaths = [ "/etc/nix/netrc" legacyTargetDirectory ];
      ReadWritePaths = [ "/var/lib/mechatron-prime" badgeDirectory ];
    };
  };

  systemd.paths.mechatron-prime-worker = {
    description = "Trigger Mechatron Prime worker when the global queue changes";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = "/var/lib/mechatron-prime/queue/builds.ndjson";
      Unit = "mechatron-prime-worker.service";
    };
  };
}
