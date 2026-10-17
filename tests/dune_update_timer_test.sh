#!/usr/bin/env bash
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$HOME/dotfiles/bin/src/capture.bash"
out="" err="" rc=0
failures=0
check() {
	local label="$1"
	shift
	if "$@" >/dev/null; then printf 'ok - %s\n' "$label"; else printf 'not ok - %s\n' "$label"; failures=$((failures + 1)); fi
}

capture nix eval --json "path:$root#nixosConfigurations.thelio-nixos.config" --apply 'c: let t = c.systemd.user.timers.dune-update-check; in { timer = { inherit (t) description timerConfig unitConfig wantedBy; }; service = c.systemd.user.services.dune-update-check.serviceConfig; }'
if [ "$rc" -ne 0 ]; then printf 'not ok - effective update timer evaluates\n'; exit 1; fi
config="$out"
check 'timer description states its schedule' jq -e '.timer.description == "Dune server update check every 3 hours"' <<< "$config"
check 'timer runs every three hours' jq -e '.timer.timerConfig.OnCalendar == "*-*-* 00/3:00:00"' <<< "$config"
check 'persistent catch-up and target service are preserved' jq -e '.timer.timerConfig.Persistent == true and .timer.timerConfig.Unit == "dune-update-check.service"' <<< "$config"
check 'user scope and timer activation are preserved' jq -e '(.timer.unitConfig.ConditionUser | length) > 0 and .timer.wantedBy == ["timers.target"]' <<< "$config"
check 'read-only update check and available-update exit are preserved' jq -e '.service.Type == "oneshot" and (.service.ExecStart | endswith(" update check --json")) and .service.SuccessExitStatus == ["1"]' <<< "$config"

# Enumerate a full UTC day and its boundary using systemd's real calendar parser.
calendar="$(jq -r '.timer.timerConfig.OnCalendar' <<< "$config")"
capture env TZ=UTC systemd-analyze calendar --base-time='2026-10-14 00:00:00 UTC' --iterations=9 "$calendar"
if [ "$rc" -ne 0 ]; then printf 'not ok - systemd accepts calendar\n'; exit 1; fi
events="$(sed -n -E 's/^ *(Next elapse|Iteration #[0-9]+):.* (2026-[0-9-]+ [0-9:]+) UTC$/\2/p' <<< "$out")"
expected='2026-10-14 03:00:00
2026-10-14 06:00:00
2026-10-14 09:00:00
2026-10-14 12:00:00
2026-10-14 15:00:00
2026-10-14 18:00:00
2026-10-14 21:00:00
2026-10-15 00:00:00
2026-10-15 03:00:00'
if [ "$events" = "$expected" ]; then
	printf 'ok - exactly eight three-hour slots per UTC day, including midnight boundary\n'
else
	printf 'not ok - three-hour slot set and next-day boundary\n'
	failures=$((failures + 1))
fi
exit "$failures"
