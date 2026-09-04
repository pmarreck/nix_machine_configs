#!/usr/bin/env bash

# Effective WSL interoperability contract for Tiki.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

interop="$({
	nix eval --json "$ROOT_DIR#nixosConfigurations.tiki-wsl-nixos.config.wsl" --apply '
		wsl: {
			appendWindowsPath = wsl.wslConf.interop.appendWindowsPath;
			interopEnabled = wsl.wslConf.interop.enabled;
			registerWindowsExecutables = wsl.interop.register;
		}
	' 2>/dev/null
})"
eval_status=$?

if [ "$eval_status" -eq 0 ]; then
	pass 'Tiki WSL interoperability settings evaluate'
else
	fail 'Tiki WSL interoperability settings must evaluate'
fi

expected='{"appendWindowsPath":false,"interopEnabled":true,"registerWindowsExecutables":true}'
if [ "$interop" = "$expected" ]; then
	pass 'Tiki omits Windows PATH while retaining explicit PE execution'
else
	fail "expected selective WSL interoperability, got [$interop]"
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
