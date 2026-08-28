#!/usr/bin/env bash

# Effective Thelio contract for the packaged Himalaya mail client.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$HOME/dotfiles/bin/src/capture.bash"

failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

out=""
err=""
rc=0
capture nix eval --option eval-cache false --raw \
	"path:$ROOT_DIR#nixosConfigurations.thelio-nixos.config.users.users.pmarreck.packages" \
	--apply 'ps: let p = builtins.head (builtins.filter (p: (p.pname or "") == "himalaya") ps); in p.version + "|" + p.drvPath'

if [ "$rc" -eq 0 ]; then
	pass "Peter's Himalaya package evaluates to a derivation"
else
	fail "Himalaya package must evaluate (exit $rc)"
fi

case "$out" in
	2.*'|'/nix/store/*-himalaya-2.*.drv)
		pass 'Thelio uses the current Himalaya 2 package'
		;;
	*)
		fail "Thelio must use Himalaya 2, got [$out]"
		;;
esac

if [[ "$err" != *'buildFeatures is deprecated'* ]]; then
	pass 'Himalaya evaluation does not use deprecated buildFeatures'
else
	fail 'Himalaya evaluation still uses deprecated buildFeatures'
fi

if [[ "$err" != *'buildNoDefaultFeatures is deprecated'* ]]; then
	pass 'Himalaya evaluation does not use deprecated buildNoDefaultFeatures'
else
	fail 'Himalaya evaluation still uses deprecated buildNoDefaultFeatures'
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
