#!/usr/bin/env bash

# Contract for modem-dev/hunk and its Thelio/Tiki placement.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

if rg -Fq 'github:modem-dev/hunk/0a3cc064931a9d576882baee6daac7cfab3d0bbe' "$ROOT_DIR/flake.nix" &&
	! rg -Fq 'builtins.getFlake "github:modem-dev/hunk/' "$ROOT_DIR/system76_thelio_nixos/configuration.nix"; then
	pass 'Hunk uses one exact top-level flake input rather than an embedded lookup'
else
	fail 'Hunk must use the known Thelio revision through a top-level flake input'
fi

package_identity="$({
	nix eval --json "$ROOT_DIR#packages.x86_64-linux.hunk" --apply '
		package: { pname = package.pname or ""; version = package.version or ""; }
	' 2>/dev/null
})"
package_status=$?
if [ "$package_status" -eq 0 ] && [ "$package_identity" = '{"pname":"hunkdiff","version":"0.16.0"}' ]; then
	pass 'flake exposes modem-dev Hunk 0.16.0 as packages.x86_64-linux.hunk'
else
	fail 'Hunk package identity must be hunkdiff 0.16.0'
fi

check_name="$(nix eval --raw "$ROOT_DIR#checks.x86_64-linux.hunk.name" 2>/dev/null)"
check_status=$?
if [ "$check_status" -eq 0 ] && [ -n "$check_name" ]; then
	pass 'flake exposes an executable Hunk smoke check'
else
	fail 'flake must expose checks.x86_64-linux.hunk'
fi

placement="$({
	nix eval --json "$ROOT_DIR#nixosConfigurations" --apply '
		configurations:
		let
			isHunk = package:
				(package.pname or "") == "hunkdiff" &&
				(package.version or "") == "0.16.0";
			placement = host: user:
				let config = configurations.${host}.config;
				in {
					user = builtins.any isHunk config.users.users.${user}.packages;
					system = builtins.any isHunk config.environment.systemPackages;
				};
		in {
			thelio = placement "thelio-nixos" "pmarreck";
			tiki = placement "tiki-wsl-nixos" "nixos";
		}
	' 2>/dev/null
})"
placement_status=$?
expected='{"thelio":{"system":true,"user":false},"tiki":{"system":false,"user":true}}'
if [ "$placement_status" -eq 0 ] && [ "$placement" = "$expected" ]; then
	pass 'Thelio retains Hunk system-wide and Tiki installs it for its active user'
else
	fail 'Hunk must retain its Thelio placement and enter Tiki user packages'
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
