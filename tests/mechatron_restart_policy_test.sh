#!/usr/bin/env bash

# A NixOS switch stops units whose definition changed and starts them again in
# a later phase. An interrupted switch left the Mechatron Prime webhook
# receiver, badge server, ops console, operator route and provisioner stopped
# for half an hour. Classify the whole long-running set from the evaluated host
# configuration: every member must restart in place (stopIfChanged = false), so
# a member that lost the policy fails by name. THELIO_FLAKE_REF may point the
# evaluation at another revision of this repository.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FLAKE_REF="${THELIO_FLAKE_REF:-$ROOT_DIR}"
failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

long_running='["mechatron-prime-badges","mechatron-prime-ops","mechatron-prime-ops-route","mechatron-prime-provision","mechatron-prime-webhook"]'

restart_in_place="$({
	nix eval --json "$FLAKE_REF#nixosConfigurations.thelio-nixos.config" --apply '
		config:
		let
			names = [ "mechatron-prime-badges" "mechatron-prime-ops" "mechatron-prime-ops-route" "mechatron-prime-provision" "mechatron-prime-webhook" ];
			restartsInPlace = name: (config.systemd.services.${name}.stopIfChanged or true) == false;
		in builtins.filter restartsInPlace names
	' 2>/dev/null
})"
status=$?

if [ "$status" -eq 0 ]; then
	pass 'Mechatron Prime activation policy evaluates'
else
	fail 'Mechatron Prime activation policy must evaluate'
fi

if [ "$restart_in_place" = "$long_running" ]; then
	pass 'every long-running Mechatron Prime service restarts in place on activation'
else
	fail "expected $long_running to restart in place, got [$restart_in_place]"
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
