{ config, lib, pkgs, ... }:

let
  thresholdPercent = 15;
  cooldownSeconds = 300;
  interval = "30s";
  accuracy = "5s";

  lowMemoryWatcher = pkgs.writeShellApplication {
    name = "low-memory-notify";
    runtimeInputs = with pkgs; [ coreutils gawk libnotify systemd util-linux ];
    text = ''
      set -euo pipefail

      total=$(awk '/MemTotal:/{print $2}' /proc/meminfo)
      avail=$(awk '/MemAvailable:/{print $2}' /proc/meminfo)
      if [ -z "''${total}" ] || [ -z "''${avail}" ]; then
        exit 0
      fi

      threshold=$(( total * ${toString thresholdPercent} / 100 ))
      if [ "''${avail}" -gt "''${threshold}" ]; then
        exit 0
      fi

      used=$(( total - avail ))
      percent_used=$(( used * 100 / total ))
      avail_human=$(numfmt --to=iec --from-unit=K "''${avail}")
      used_human=$(numfmt --to=iec --from-unit=K "''${used}")
      total_human=$(numfmt --to=iec --from-unit=K "''${total}")
      message="Available ''${avail_human} of ''${total_human} (~''${percent_used}% used; ''${used_human} used)."

      state_dir="''${XDG_RUNTIME_DIR:-/run/user/$UID}"
      mkdir -p "''${state_dir}"
      state_file="''${state_dir}/low-memory-notify.last"
      now=$(date +%s)
      min_interval=${toString cooldownSeconds}
      if [ "''${min_interval}" -gt 0 ] && [ -f "''${state_file}" ]; then
        last=$(cat "''${state_file}" 2>/dev/null || echo 0)
        if [ "''${last}" -gt 0 ] && [ $(( now - last )) -lt "''${min_interval}" ]; then
          exit 0
        fi
      fi

      systemd-cat --identifier=low-memory-notify echo "Memory pressure detected: ''${message} Threshold ${toString thresholdPercent}% available."
      notify-send --urgency=critical "Low memory warning" "''${message}"
      echo "''${now}" > "''${state_file}"
    '';
  };
in
{
  environment.systemPackages = [ pkgs.libnotify ];

  systemd.user.services.low-memory-notify = {
    unitConfig = {
      Description = "Low memory notifier";
      After = [ "graphical-session.target" ];
      ConditionPathExists = "/proc/meminfo";
    };
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lowMemoryWatcher}/bin/low-memory-notify";
    };
  };

  systemd.user.timers.low-memory-notify = {
    unitConfig = {
      Description = "Run low memory notifier periodically";
    };
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = interval;
      AccuracySec = accuracy;
    };
    wantedBy = [ "timers.target" ];
  };
}
