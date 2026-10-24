#!/usr/bin/env bash

# The dotfiles host suite depends on three system-wide tools being declared for
# Thelio: mise (shell shims for Node), b3sum (repo-maintenance state keys) and
# expect (timed PTY assertions). Classify the whole set from the evaluated
# configuration so a missing member fails by name rather than by presence check.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

required_tools='["b3sum","expect","mise"]'

declared="$({
	nix eval --json "$ROOT_DIR#nixosConfigurations.thelio-nixos.config" --apply '
		config:
		let
			required = [ "b3sum" "expect" "mise" ];
			names = map (package: package.pname or "") config.environment.systemPackages;
		in builtins.filter (name: builtins.elem name names) required
	' 2>/dev/null
})"
status=$?

if [ "$status" -eq 0 ]; then
	pass 'Thelio host-tool contract evaluates'
else
	fail 'Thelio host-tool contract must evaluate'
fi

if [ "$declared" = "$required_tools" ]; then
	pass 'Thelio declares b3sum, expect and mise as system packages'
else
	fail "expected $required_tools declared, got [$declared]"
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
