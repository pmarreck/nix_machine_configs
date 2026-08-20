#!/usr/bin/env bash

# Contract for the exact Nix outputs built by Mechatron Prime CI.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TARGETS="$ROOT_DIR/.mechatron-prime/targets"
README="$ROOT_DIR/README.md"

failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

expected_targets="$({
	printf '%s\n' \
		'checks.x86_64-linux.codex-app' \
		'checks.x86_64-linux.tode' \
		'nixosConfigurations.framework-nixos.config.system.build.toplevel' \
		'nixosConfigurations.thelio-nixos.config.system.build.toplevel' \
		'nixosConfigurations.tiki-wsl-nixos.config.system.build.toplevel'
} | sort)"

if [ -f "$TARGETS" ]; then
	pass 'Mechatron target manifest exists'
	actual_targets="$(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$TARGETS" | sort)"
	if [ "$actual_targets" = "$expected_targets" ]; then
		pass 'Mechatron targets are the exact intentional five-output set'
	else
		fail 'Mechatron targets must cover all hosts and both executable smoke checks exactly'
	fi

	resolved=0
	while IFS= read -r target; do
		[ -n "$target" ] || continue
		if nix eval --raw "$ROOT_DIR#$target.drvPath" >/dev/null 2>&1; then
			resolved=$((resolved + 1))
		fi
	done <<EOF
$expected_targets
EOF
	if [ "$resolved" -eq 5 ]; then
		pass 'every declared Mechatron target resolves to a derivation'
	else
		fail 'every declared Mechatron target must resolve to a derivation'
	fi
else
	fail 'Mechatron target manifest exists'
	fail 'Mechatron targets are the exact intentional five-output set'
	fail 'every declared Mechatron target resolves to a derivation'
fi

badge='[![Mechatron Prime CI](https://img.shields.io/endpoint?url=https%3A%2F%2Fthelio-nixos.tail66c90.ts.net%2Fbadges%2Fnix_machine_configs.json&style=for-the-badge)](https://thelio-nixos.tail66c90.ts.net/mechatron-prime/)'
if [ -f "$README" ] && rg -Fqx "$badge" "$README"; then
	pass 'README carries the canonical dynamic Mechatron badge'
else
	fail 'README must carry the canonical dynamic Mechatron badge'
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
