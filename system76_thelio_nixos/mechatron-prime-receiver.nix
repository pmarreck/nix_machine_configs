# Mechatron Prime — GitHub webhook receiver.
#
# Public ingress is Tailscale Funnel. This service itself binds localhost only
# and relies on GitHub's HMAC-SHA256 webhook signature before executing the
# handler.
{ lib, pkgs, ... }:
let
  allowlistedRepos = [
    "blar"
    "BLIP"
    "blip_mp"
    "bzip2z"
    "capy"
    "chardetz"
    "chatscan"
    "codescan"
    "cols"
    "compact_pro"
    "deflate_fingerprint"
    "difz"
    "dirtree"
    "docscan"
    "entropy-shield"
    "ffpw"
    "incitez"
    "jp2z"
    "jpegz"
    "llvm-lsp"
    "mandelbrot-zig-tui"
    "par2z"
    "progrez"
    "rarz"
    "systat"
    "tiffz"
    "validate"
    "warp-history"
    "z7z"
  ];

  allowlistPath = "/etc/mechatron-prime/repos.allowlist";
  allowlistSeedFile = pkgs.writeText "mechatron-prime-repos.allowlist"
    (lib.concatStringsSep "\n" allowlistedRepos + "\n");

  handler = pkgs.writeShellApplication {
    name = "mechatron-prime-webhook-handler";
    runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.util-linux ];
    text = ''
      set -u
      umask 027

      state_dir="''${MECHATRON_STATE_DIR:-/var/lib/mechatron-prime}"
      allowlist="''${MECHATRON_REPOS_ALLOWLIST:-${allowlistPath}}"
      install -d -m 0750 "$state_dir" "$state_dir/logs" "$state_dir/queue"
      queue_file="$state_dir/queue/validate.ndjson"
      queue_lock="$state_dir/queue/.validate.lock"

      event="''${GITHUB_EVENT:-}"
      delivery="''${GITHUB_DELIVERY:-}"
      repo="''${GITHUB_REPOSITORY:-}"
      ref="''${GITHUB_REF:-}"
      sha="''${GITHUB_SHA:-}"
      repo_name="''${repo##*/}"
      ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

      allowed=false
      if [ -n "$repo_name" ] && [ -f "$allowlist" ]; then
        while IFS= read -r line; do
          case "$line" in ""|\#*) continue ;; esac
          if [ "$line" = "$repo_name" ] || [ "$line" = "$repo" ]; then allowed=true; break; fi
        done < "$allowlist"
      fi

      jq -cn \
        --arg ts "$ts" \
        --arg event "$event" \
        --arg delivery "$delivery" \
        --arg repo "$repo" \
        --arg ref "$ref" \
        --arg sha "$sha" \
        --argjson allowed "$allowed" \
        '{ts:$ts,event:$event,delivery:$delivery,repo:$repo,ref:$ref,sha:$sha,allowed:$allowed}' \
        >> "$state_dir/events.ndjson"

      if [ "$event" = "ping" ]; then
        echo "Mechatron Prime ping accepted"
        exit 0
      fi

      if [ "$allowed" != true ]; then
        echo "Mechatron Prime ignored non-allowlisted repo: $repo"
        exit 0
      fi

      if [ "$event" != "push" ]; then
        echo "Mechatron Prime ignored event: $event"
        exit 0
      fi

      if [ "$repo" != "pmarreck/validate" ]; then
        echo "Mechatron Prime MVP currently pilots validate only; ignored: $repo"
        exit 0
      fi

      if [ "$ref" != "refs/heads/yolo" ]; then
        echo "Mechatron Prime MVP currently builds yolo only; ignored: $ref"
        exit 0
      fi

      exec 9>"$queue_lock"
      flock 9
      jq -cn \
        --arg ts "$ts" \
        --arg delivery "$delivery" \
        --arg repo "$repo" \
        --arg ref "$ref" \
        --arg sha "$sha" \
        '{ts:$ts,delivery:$delivery,repo:$repo,ref:$ref,sha:$sha,status:"queued"}' \
        >> "$queue_file"
      chmod 0640 "$queue_file"

      echo "Mechatron Prime queued validate@$sha"
    '';
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
              match: {
                type: "payload-hmac-sha256",
                secret: $secret,
                parameter: {source: "header", name: "X-Hub-Signature-256"}
              }
            }
          }
        ]
      ' > /run/mechatron-prime/hooks.json
    '';
  };
in
{
  users.groups.mechatron-prime = { };
  users.users.mechatron-prime = {
    isSystemUser = true;
    group = "mechatron-prime";
    home = "/var/lib/mechatron-prime";
    createHome = true;
  };

  systemd.tmpfiles.rules = [
    "d /etc/mechatron-prime 0710 root mechatron-prime - -"
    "C /etc/mechatron-prime/repos.allowlist - - - - ${allowlistSeedFile}"
    "z /etc/mechatron-prime/repos.allowlist 0640 root mechatron-prime - -"
    "d /var/lib/mechatron-prime 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/logs 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/queue 0750 mechatron-prime mechatron-prime - -"
    "z /var/lib/mechatron-prime/events.ndjson 0640 mechatron-prime mechatron-prime - -"
    "z /var/lib/mechatron-prime/queue/validate.ndjson 0640 mechatron-prime mechatron-prime - -"
  ];

  systemd.services.mechatron-prime-webhook = {
    description = "Mechatron Prime GitHub webhook receiver";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    environment = {
      MECHATRON_STATE_DIR = "/var/lib/mechatron-prime";
      MECHATRON_REPOS_ALLOWLIST = "${allowlistPath}";
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
}
