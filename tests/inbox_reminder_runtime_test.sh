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

capture nix eval --json "$root#nixosConfigurations.thelio-nixos.config" --apply 'c: let s = c.systemd.user.services.llmsend-inbox-remind; t = c.systemd.user.timers.llmsend-inbox-remind; in { service = { inherit (s) serviceConfig unitConfig wantedBy after wants requires partOf; }; timer = { inherit (t) timerConfig unitConfig wantedBy; }; owner = c.services.unix-mail-redux.owner; }'
if [ "$rc" -ne 0 ]; then printf 'not ok - effective reminder service and timer evaluate\n'; exit 1; fi
config="$out"
check 'one bounded oneshot treats deferral as an outcome' jq -e '.service.serviceConfig | .Type == "oneshot" and .TimeoutStartSec == 90 and .SuccessExitStatus == [3]' <<< "$config"
check 'private persistent state and restrictive creation mode' jq -e '.service.serviceConfig | .StateDirectory == "llmsend-reminders" and .StateDirectoryMode == "0700" and .UMask == "0077"' <<< "$config"
check 'immutable packaged command reads only the private operator config' jq -e '.service.serviceConfig.ExecStart | test("^/nix/store/[a-z0-9]+-llmsend-inbox-remind/bin/llmsend-inbox-remind --config %h/\\.config/llmsend-reminders/config\\.json$")' <<< "$config"
check 'read-only home with private state and Unix transport retained' jq -e '.service.serviceConfig | .NoNewPrivileges == true and .PrivateTmp == true and .ProtectSystem == "strict" and .ProtectHome == "read-only" and .RestrictAddressFamilies == ["AF_UNIX"]' <<< "$config"
check 'only the configured operator may run either unit' jq -e '.owner as $owner | ($owner | length) > 0 and .service.unitConfig.ConditionUser == $owner and .timer.unitConfig.ConditionUser == $owner' <<< "$config"
check 'absent private config is visible as a skipped service' jq -e '.service.unitConfig.ConditionPathExists == "%h/.config/llmsend-reminders/config.json"' <<< "$config"
check 'persistent minutely poll targets only this singleton service' jq -e '.timer.timerConfig.OnCalendar == "minutely" and .timer.timerConfig.Persistent == true and .timer.timerConfig.Unit == "llmsend-inbox-remind.service" and .timer.wantedBy == ["timers.target"]' <<< "$config"
check 'timer alone schedules work without shared service dependencies' jq -e '.service | .wantedBy == [] and .after == [] and .wants == [] and .requires == [] and .partOf == []' <<< "$config"
check 'portable source input is immutable and lock-consistent' jq -e '.nodes.root.inputs.llmsend_reminders as $node | .nodes[$node] | .original.type == "github" and .locked.type == "github" and .original.rev == .locked.rev and (.locked.rev | test("^[0-9a-f]{40}$"))' "$root/flake.lock"

capture env TZ=UTC systemd-analyze calendar --base-time='2026-10-14 17:00:00 UTC' --iterations=3 'minutely'
if [ "$rc" -ne 0 ]; then printf 'not ok - systemd accepts reminder calendar\n'; exit 1; fi
events="$(sed -n -E 's/^ *(Next elapse|Iteration #[0-9]+):.* (2026-[0-9-]+ [0-9:]+) UTC$/\2/p' <<< "$out")"
expected='2026-10-14 17:01:00
2026-10-14 17:02:00
2026-10-14 17:03:00'
if [ "$events" = "$expected" ]; then printf 'ok - real calendar parser yields one-minute deadlines\n'; else printf 'not ok - real calendar deadline set\n'; failures=$((failures + 1)); fi
exit "$failures"
