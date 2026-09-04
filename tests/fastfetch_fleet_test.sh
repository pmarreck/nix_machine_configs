#!/usr/bin/env bash

# Effective package contract for every NixOS host declared by this flake.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

placement="$({
	nix eval --json "$ROOT_DIR#nixosConfigurations" --apply '
		configurations:
		let
			isFastfetch = package: (package.pname or "") == "fastfetch";
			hasFastfetch = host: user:
				let config = configurations.${host}.config;
				in builtins.any isFastfetch (
					config.environment.systemPackages ++
					config.users.users.${user}.packages
				);
		in {
			framework = hasFastfetch "framework-nixos" "pmarreck";
			thelio = hasFastfetch "thelio-nixos" "pmarreck";
			tiki = hasFastfetch "tiki-wsl-nixos" "nixos";
		}
	' 2>/dev/null
})"
placement_status=$?

if [ "$placement_status" -eq 0 ]; then
	pass 'all declared NixOS host package sets evaluate'
else
	fail 'declared NixOS host package sets must evaluate'
fi

expected='{"framework":true,"thelio":true,"tiki":true}'
if [ "$placement" = "$expected" ]; then
	pass 'Fastfetch is available to the active human on every NixOS host'
else
	fail "expected Fastfetch on every NixOS host, got [$placement]"
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
