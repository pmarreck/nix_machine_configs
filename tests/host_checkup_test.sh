#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
host="${NIXOS_HOSTNAME:-$(hostname)}"
# Nix progress such as "copying path" lines goes to stderr; mixing it into the
# JSON made the calendar check fail whenever an evaluation had to fetch.
eval_errors="$(mktemp "${TMPDIR:-/tmp}/host-checkup-eval.XXXXXX")"
trap 'rm -f "$eval_errors"' EXIT
output="$(nix eval --json "$root#nixosConfigurations.\"$host\".config" --apply 'c: { text = c.systemd.user.units."mechatron-checkup.service".text; service = c.systemd.user.services.mechatron-checkup.serviceConfig; delivery = c.systemd.user.services.mechatron-checkup-delivery.serviceConfig; timer = c.systemd.user.timers.mechatron-checkup.timerConfig; retry = c.systemd.user.timers.mechatron-checkup-delivery.timerConfig; }' 2>"$eval_errors")"
status=$?
if [ "$status" -ne 0 ]; then printf 'not ok - effective checkup configuration evaluates\n'; cat "$eval_errors" >&2; exit 1; fi
if ! jq -e '
 .timer.OnCalendar == "*-*-* 00/3:00:00" and .timer.Persistent == true and
 .retry.OnCalendar == "minutely" and (.delivery.ExecStart | type) == "string"
' <<< "$output" >/dev/null 2>&1; then printf 'not ok - effective monitoring calendars\n'; exit 1; fi
if ! jq -e '.service | .PrivateTmp == false and .ProtectHome == false and .ProtectSystem == false and .ReadWritePaths == [] and .NoNewPrivileges == true and .MemoryMax == "256M" and .TimeoutStartSec == 120' <<< "$output" >/dev/null 2>&1; then printf 'not ok - host visibility and monitor bounds\n'; exit 1; fi
printf 'host checkup: PASS\n'
