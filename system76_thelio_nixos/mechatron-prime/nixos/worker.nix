# Mechatron Prime — sequential allowlisted multi-repository Nix worker.
{ lib, pkgs, ... }:
let
  repoPolicies = import ./repos.nix;
  repoRefPolicies = import ./repo-refs.nix;
  allowlistPath = "/etc/mechatron-prime/repos.allowlist";
  repoRefPath = "/etc/mechatron-prime/repo-refs";
  targetDirectory = "/etc/mechatron-prime/targets";
  badgeDirectory = "/var/lib/mechatron-prime-public/badges";
  repoRefSeedFile =
    assert builtins.attrNames repoPolicies == builtins.attrNames repoRefPolicies;
    assert lib.all (ref: builtins.match "refs/heads/[A-Za-z0-9._/-]+" ref != null) (builtins.attrValues repoRefPolicies);
    pkgs.writeText "mechatron-prime-repo-refs"
      (lib.concatStringsSep "\n" (lib.mapAttrsToList (repo: ref: "${repo}\t${ref}") repoRefPolicies) + "\n");

  targetSeedRules = lib.mapAttrsToList
    (repo: targets:
      let
        repoName = lib.last (lib.splitString "/" repo);
        seed = pkgs.writeText "mechatron-prime-${repoName}-targets"
          (lib.concatStringsSep "\n" targets + "\n");
      in
        "L+ ${targetDirectory}/${repoName}.targets - - - - ${seed}")
    repoPolicies;

  worker = pkgs.writeShellApplication {
    name = "mechatron-prime-worker";
    runtimeInputs = [
      pkgs.attic-client
      pkgs.coreutils
      pkgs.jq
      pkgs.nix
      pkgs.util-linux
    ];
    text = builtins.readFile ../scripts/policy.bash
      + "\n"
      + builtins.readFile ../scripts/worker.bash;
  };
in
{
  systemd.tmpfiles.rules = [
    "d /etc/mechatron-prime 0710 root mechatron-prime - -"
    "L+ ${repoRefPath} - - - - ${repoRefSeedFile}"
    "d ${targetDirectory} 0750 root mechatron-prime - -"
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
    "f /var/lib/mechatron-prime/current.json 0640 mechatron-prime mechatron-prime - -"
  ] ++ targetSeedRules;

  systemd.services.mechatron-prime-worker = {
    description = "Mechatron Prime sequential multi-repository build worker";
    after = [ "network-online.target" "atticd.service" "nix-daemon.service" ];
    wants = [ "network-online.target" "atticd.service" ];

    environment = {
      HOME = "/var/lib/mechatron-prime";
      XDG_CACHE_HOME = "/var/lib/mechatron-prime/.cache";
      XDG_CONFIG_HOME = "/var/lib/mechatron-prime/.config";
      MECHATRON_STATE_DIR = "/var/lib/mechatron-prime";
      MECHATRON_REPOS_ALLOWLIST = allowlistPath;
      MECHATRON_REPO_REFS = repoRefPath;
      MECHATRON_TARGETS_DIR = targetDirectory;
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
      ExecStart = "${worker}/bin/mechatron-prime-worker";
      TimeoutStartSec = "6h";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadOnlyPaths = [ "/etc/nix/netrc" "/etc/mechatron-prime" ];
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
