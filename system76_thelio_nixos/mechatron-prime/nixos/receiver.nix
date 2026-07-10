# Mechatron Prime — authenticated GitHub webhook receiver and public badges.
{ lib, pkgs, ... }:
let
  repoPolicies = import ./repos.nix;
  allowlistedRepos = builtins.attrNames repoPolicies;
  allowlistPath = "/etc/mechatron-prime/repos.allowlist";
  publicDirectory = "/var/lib/mechatron-prime-public";
  badgeDirectory = "${publicDirectory}/badges";
  allowlistSeedFile = pkgs.writeText "mechatron-prime-repos.allowlist"
    (lib.concatStringsSep "\n" allowlistedRepos + "\n");

  badgeSeedRules = lib.mapAttrsToList
    (repo: _:
      let
        repoName = lib.last (lib.splitString "/" repo);
        seed = pkgs.writeText "mechatron-prime-${repoName}-badge.json"
          ''{"schemaVersion":1,"label":"🤖 Mechatron Prime","message":"UNKNOWN","color":"lightgrey","isError":false}\n'';
      in
        "C ${badgeDirectory}/${repoName}.json 0640 mechatron-prime mechatron-prime-badges - ${seed}")
    repoPolicies;

  handler = pkgs.writeShellApplication {
    name = "mechatron-prime-webhook-handler";
    runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.util-linux ];
    text = builtins.readFile ../scripts/policy.bash
      + "\n"
      + builtins.readFile ../scripts/receiver.bash;
  };

  renderHooks = pkgs.writeShellApplication {
    name = "mechatron-prime-render-hooks";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      set -u
      : "''${MECHATRON_GITHUB_WEBHOOK_SECRET:?missing webhook secret}"
      umask 077

      jq -n --arg secret "$MECHATRON_GITHUB_WEBHOOK_SECRET" --arg handler "${handler}/bin/mechatron-prime-webhook-handler" '
        [
          {
            id: "github",
            "execute-command": $handler,
            "command-working-directory": "/var/lib/mechatron-prime",
            "response-message": "Mechatron Prime accepted webhook",
            "include-command-output-in-response": false,
            "pass-environment-to-command": [
              {source: "header", name: "X-GitHub-Event", envname: "GITHUB_EVENT"},
              {source: "header", name: "X-GitHub-Delivery", envname: "GITHUB_DELIVERY"},
              {source: "payload", name: "repository.full_name", envname: "GITHUB_REPOSITORY"},
              {source: "payload", name: "ref", envname: "GITHUB_REF"},
              {source: "payload", name: "after", envname: "GITHUB_SHA"}
            ],
            "trigger-rule": {
              and: [
                {
                  match: {
                    type: "payload-hmac-sha256",
                    secret: $secret,
                    parameter: {source: "header", name: "X-Hub-Signature-256"}
                  }
                },
                {
                  match: {
                    type: "value", value: "push",
                    parameter: {source: "header", name: "X-GitHub-Event"}
                  }
                }
              ]
            }
          }
        ]
      ' > /run/mechatron-prime/hooks.json
    '';
  };
in
{
  users.groups.mechatron-prime = { };
  users.groups.mechatron-prime-badges = { };

  users.users.mechatron-prime = {
    isSystemUser = true;
    group = "mechatron-prime";
    home = "/var/lib/mechatron-prime";
    createHome = true;
  };

  users.users.mechatron-prime-badges = {
    isSystemUser = true;
    group = "mechatron-prime-badges";
  };

  systemd.tmpfiles.rules = [
    "d /etc/mechatron-prime 0710 root mechatron-prime - -"
    "C+ /etc/mechatron-prime/repos.allowlist - - - - ${allowlistSeedFile}"
    "z /etc/mechatron-prime/repos.allowlist 0640 root mechatron-prime - -"
    "d /var/lib/mechatron-prime 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/logs 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/queue 0750 mechatron-prime mechatron-prime - -"
    "f /var/lib/mechatron-prime/accepted.ndjson 0640 mechatron-prime mechatron-prime - -"
    "f /var/lib/mechatron-prime/events.ndjson 0640 mechatron-prime mechatron-prime - -"
    "f /var/lib/mechatron-prime/queue/builds.ndjson 0640 mechatron-prime mechatron-prime - -"
    "d ${publicDirectory} 0750 mechatron-prime mechatron-prime-badges - -"
    "d ${badgeDirectory} 2750 mechatron-prime mechatron-prime-badges - -"
  ] ++ badgeSeedRules;

  systemd.services.mechatron-prime-webhook = {
    description = "Mechatron Prime GitHub webhook receiver";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      MECHATRON_STATE_DIR = "/var/lib/mechatron-prime";
      MECHATRON_REPOS_ALLOWLIST = allowlistPath;
    };

    serviceConfig = {
      User = "mechatron-prime";
      Group = "mechatron-prime";
      EnvironmentFile = "/etc/mechatron-prime/github-webhook.env";
      RuntimeDirectory = "mechatron-prime";
      RuntimeDirectoryMode = "0700";
      StateDirectory = "mechatron-prime";
      StateDirectoryMode = "0750";
      ExecStartPre = "${renderHooks}/bin/mechatron-prime-render-hooks";
      ExecStart = "${pkgs.webhook}/bin/webhook -ip 127.0.0.1 -port 9000 -hooks /run/mechatron-prime/hooks.json -http-methods POST -verbose";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/mechatron-prime" "/run/mechatron-prime" ];
    };
  };

  systemd.services.mechatron-prime-badges = {
    description = "Mechatron Prime public read-only badge endpoint";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig = {
      User = "mechatron-prime-badges";
      Group = "mechatron-prime-badges";
      ExecStart = "${pkgs.darkhttpd}/bin/darkhttpd ${publicDirectory} --addr 127.0.0.1 --port 9001 --no-listing --hide-dotfiles --default-mimetype application/json --no-server-id";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadOnlyPaths = [ publicDirectory ];
      InaccessiblePaths = [ "/var/lib/mechatron-prime" "/etc/mechatron-prime" "/etc/nix" ];
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
    };
  };
}
