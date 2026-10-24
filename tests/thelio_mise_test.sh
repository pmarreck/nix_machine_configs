#!/usr/bin/env bash

# Thelio mirrors Framework's declarative pattern for user-facing runtime tools:
# a global system package with nix-ld available for downloaded tool binaries.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

contract="$({
	nix eval --json "$ROOT_DIR#nixosConfigurations.thelio-nixos.config" --apply '
		config:
		let
			isMise = package: (package.pname or "") == "mise";
		in {
			miseInSystemPackages = builtins.any isMise config.environment.systemPackages;
			nixLdEnabled = config.programs.nix-ld.enable;
		}
	' 2>/dev/null
})"
status=$?

if [ "$status" -eq 0 ]; then
	pass 'Thelio mise contract evaluates'
else
	fail 'Thelio mise contract must evaluate'
fi

expected='{"miseInSystemPackages":true,"nixLdEnabled":true}'
if [ "$contract" = "$expected" ]; then
	pass 'Thelio installs mise globally with nix-ld enabled'
else
	fail "expected $expected, got [$contract]"
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
