#!/usr/bin/env bash

# Preserve Tiki packages found in its clean, unpushed local configuration commit.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

packages="$({
	nix eval --json "$ROOT_DIR#nixosConfigurations.tiki-wsl-nixos.config.environment.systemPackages" \
		--apply 'builtins.map (package: package.pname or package.name or "")' 2>/dev/null
})"
eval_status=$?

for package in halloy sniffnet; do
	if [ "$eval_status" -eq 0 ] && jq -e --arg package "$package" 'index($package) != null' <<<"$packages" >/dev/null; then
		pass "Tiki retains $package from its local package commit"
	else
		fail "Tiki must retain $package from its local package commit"
	fi
done

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
