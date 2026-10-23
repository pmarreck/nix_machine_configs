#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
host="${NIXOS_HOSTNAME:-$(hostname)}"
output="$(nix eval --json "$root#nixosConfigurations.\"$host\".config" --apply 'c: { text = c.systemd.user.units."mechatron-checkup.service".text; service = c.systemd.user.services.mechatron-checkup.serviceConfig; delivery = c.systemd.user.services.mechatron-checkup-delivery.serviceConfig; timer = c.systemd.user.timers.mechatron-checkup.timerConfig; retry = c.systemd.user.timers.mechatron-checkup-delivery.timerConfig; }' 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then printf 'not ok - effective checkup configuration evaluates\n'; exit 1; fi
if ! jq -e '
 .timer.OnCalendar == "*-*-* 00/3:00:00" and .timer.Persistent == true and
 .retry.OnCalendar == "minutely" and (.delivery.ExecStart | type) == "string"
' <<< "$output" >/dev/null 2>&1; then printf 'not ok - effective monitoring calendars\n'; exit 1; fi
if ! jq -e '.service | .PrivateTmp == false and .ProtectHome == false and .ProtectSystem == false and .ReadWritePaths == [] and .NoNewPrivileges == true and .MemoryMax == "256M" and .TimeoutStartSec == 120' <<< "$output" >/dev/null 2>&1; then printf 'not ok - host visibility and monitor bounds\n'; exit 1; fi
printf 'host checkup: PASS\n'
