# Mechatron Prime — minimal queue worker.
#
# Drains webhook queue records, builds validate from the GitHub SHA with Nix,
# and pushes successful outputs to the tailnet-local Attic cache.
{ lib, pkgs, ... }:
let
  targetPath = "/etc/mechatron-prime/validate-targets";
  targetSeedFile = pkgs.writeText "mechatron-prime-validate-targets"
    (lib.concatStringsSep "\n" [
      "packages.x86_64-linux.default"
    ] + "\n");

  worker = pkgs.writeShellApplication {
    name = "mechatron-prime-worker";
    runtimeInputs = [
      pkgs.attic-client
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.jq
      pkgs.nix
      pkgs.util-linux
    ];
    text = ''
      set -euo pipefail
      umask 027

      state_dir="''${MECHATRON_STATE_DIR:-/var/lib/mechatron-prime}"
      queue_file="$state_dir/queue/validate.ndjson"
      queue_lock="$state_dir/queue/.validate.lock"
      targets_file="''${MECHATRON_VALIDATE_TARGETS:-${targetPath}}"
      results_file="$state_dir/results.ndjson"
      build_timeout="''${MECHATRON_BUILD_TIMEOUT_SECONDS:-7200}"

      mkdir -p "$state_dir/queue" "$state_dir/batches" "$state_dir/logs" "$state_dir/work"
      touch "$queue_file" "$results_file"
      chmod 0640 "$queue_file" "$results_file"

      batch_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
      batch="$state_dir/batches/validate-$batch_id.ndjson"

      exec 9>"$queue_lock"
      flock 9
      if [ ! -s "$queue_file" ]; then
        echo "Mechatron Prime worker: queue empty"
        exit 0
      fi
      cp "$queue_file" "$batch"
      : > "$queue_file"
      chmod 0640 "$batch" "$queue_file"
      exec 9>&-

      echo "Mechatron Prime worker: draining $batch"

      while IFS= read -r item; do
        [ -n "$item" ] || continue

        repo="$(jq -r '.repo // empty' <<< "$item")"
        ref="$(jq -r '.ref // empty' <<< "$item")"
        sha="$(jq -r '.sha // empty' <<< "$item")"
        delivery="$(jq -r '.delivery // empty' <<< "$item")"
        started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        short_sha="$sha"
        if [ "''${#short_sha}" -gt 12 ]; then
          short_sha="''${short_sha:0:12}"
        fi
        run_id="$batch_id-$short_sha"
        log_file="$state_dir/logs/validate-$run_id.log"
        paths_file="$state_dir/work/validate-$run_id.paths"
        target_list="$state_dir/work/validate-$run_id.targets"
        status="success"
        failure_stage=""
        failure_detail=""

        : > "$log_file"
        : > "$paths_file"
        : > "$target_list"
        chmod 0640 "$log_file" "$paths_file" "$target_list"

        {
          echo "started_at=$started_at"
          echo "delivery=$delivery"
          echo "repo=$repo"
          echo "ref=$ref"
          echo "sha=$sha"
        } >> "$log_file"

        if [ "$repo" != "pmarreck/validate" ]; then
          status="skipped"
          failure_stage="repo-policy"
          failure_detail="worker currently pilots pmarreck/validate only"
        elif [[ ! "$sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
          status="failure"
          failure_stage="input-validation"
          failure_detail="sha is not a 40-hex Git commit"
        elif [ ! -s "$targets_file" ]; then
          status="failure"
          failure_stage="configuration"
          failure_detail="target file is empty or missing: $targets_file"
        else
          grep -Ev '^[[:space:]]*($|#)' "$targets_file" > "$target_list" || true
          chmod 0640 "$target_list"

          if [ ! -s "$target_list" ]; then
            status="failure"
            failure_stage="configuration"
            failure_detail="target file has no active targets: $targets_file"
          else
            flake="github:$repo/$sha"
            while IFS= read -r target; do
              [ -n "$target" ] || continue
              case "$target" in
                *[!A-Za-z0-9_.-]*)
                  status="failure"
                  failure_stage="target-validation"
                  failure_detail="invalid target name: $target"
                  break
                  ;;
              esac

              target_paths="$state_dir/work/validate-$run_id-$(printf '%s' "$target" | tr -c 'A-Za-z0-9_.-' '_').paths"
              {
                echo
                echo "=== nix build $flake#$target ==="
                date -u +%Y-%m-%dT%H:%M:%SZ
              } >> "$log_file"

              if timeout "$build_timeout" nix build --no-link --print-out-paths "$flake#$target" > "$target_paths" 2>> "$log_file"; then
                cat "$target_paths" >> "$paths_file"
              else
                status="failure"
                failure_stage="nix-build"
                failure_detail="target failed: $target"
                break
              fi
            done < "$target_list"
          fi
        fi

        if [ "$status" = "success" ] && [ -s "$paths_file" ]; then
          sort -u "$paths_file" > "$paths_file.sorted"
          {
            echo
            echo "=== attic push local:fleet ==="
            date -u +%Y-%m-%dT%H:%M:%SZ
          } >> "$log_file"

          if ! attic push --stdin local:fleet < "$paths_file.sorted" >> "$log_file" 2>&1; then
            status="failure"
            failure_stage="attic-push"
            failure_detail="failed to push build outputs to local:fleet"
          fi
        elif [ "$status" = "success" ]; then
          status="failure"
          failure_stage="nix-build"
          failure_detail="build produced no output paths"
        fi

        finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        targets_json="$(jq -Rsc 'split("\n") | map(select(length > 0))' < "$target_list" 2>/dev/null || printf '[]')"
        paths_json="$(jq -Rsc 'split("\n") | map(select(length > 0))' < "$paths_file" 2>/dev/null || printf '[]')"

        jq -cn \
          --arg started_at "$started_at" \
          --arg finished_at "$finished_at" \
          --arg delivery "$delivery" \
          --arg repo "$repo" \
          --arg ref "$ref" \
          --arg sha "$sha" \
          --arg status "$status" \
          --arg failure_stage "$failure_stage" \
          --arg failure_detail "$failure_detail" \
          --arg log "$log_file" \
          --argjson targets "$targets_json" \
          --argjson paths "$paths_json" \
          '{started_at:$started_at,finished_at:$finished_at,delivery:$delivery,repo:$repo,ref:$ref,sha:$sha,status:$status,failure_stage:$failure_stage,failure_detail:$failure_detail,targets:$targets,paths:$paths,log:$log}' \
          >> "$results_file"

        chmod 0640 "$results_file"
        echo "Mechatron Prime worker: $repo@$sha => $status ($failure_stage)"
      done < "$batch"
    '';
  };
in
{
  systemd.tmpfiles.rules = [
    "d /etc/mechatron-prime 0710 root mechatron-prime - -"
    "C /etc/mechatron-prime/validate-targets - - - - ${targetSeedFile}"
    "z /etc/mechatron-prime/validate-targets 0640 root mechatron-prime - -"
    "z /etc/nix/netrc 0640 root mechatron-prime - -"

    "d /var/lib/mechatron-prime 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/.cache 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/.config 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/.config/attic 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/batches 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/logs 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/queue 0750 mechatron-prime mechatron-prime - -"
    "d /var/lib/mechatron-prime/work 0750 mechatron-prime mechatron-prime - -"
    "f /var/lib/mechatron-prime/queue/validate.ndjson 0640 mechatron-prime mechatron-prime - -"
    "f /var/lib/mechatron-prime/results.ndjson 0640 mechatron-prime mechatron-prime - -"
  ];

  systemd.services.mechatron-prime-worker = {
    description = "Mechatron Prime validate build worker";
    after = [ "network-online.target" "atticd.service" "nix-daemon.service" ];
    wants = [ "network-online.target" "atticd.service" ];

    environment = {
      HOME = "/var/lib/mechatron-prime";
      XDG_CACHE_HOME = "/var/lib/mechatron-prime/.cache";
      XDG_CONFIG_HOME = "/var/lib/mechatron-prime/.config";
      MECHATRON_STATE_DIR = "/var/lib/mechatron-prime";
      MECHATRON_VALIDATE_TARGETS = targetPath;
      MECHATRON_BUILD_TIMEOUT_SECONDS = "7200";
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
      ReadWritePaths = [ "/var/lib/mechatron-prime" ];
    };
  };

  systemd.paths.mechatron-prime-worker = {
    description = "Trigger Mechatron Prime worker when validate queue changes";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = "/var/lib/mechatron-prime/queue/validate.ndjson";
      Unit = "mechatron-prime-worker.service";
    };
  };
}
