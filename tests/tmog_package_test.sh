#!/usr/bin/env bash

# Contract for the official binary-only Task Manager TMOG package.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PACKAGE="$ROOT_DIR/packages/tmog.nix"

failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

if [ -f "$PACKAGE" ] &&
	rg -Fq 'appimageTools.wrapType2' "$PACKAGE" &&
	rg -Fq 'lib.licenses.unfree' "$PACKAGE" &&
	! rg -Fq 'lib.licenses.unfreeRedistributable' "$PACKAGE"; then
	pass 'package wraps the official AppImage under its non-redistributable license'
else
	fail 'package must wrap the AppImage and must not claim redistribution rights'
fi

if ! rg -Fq 'file+https://tmog.org/version.txt' "$ROOT_DIR/flake.nix" &&
	rg -q 'file\+https://tmog\.org/rtm/downloads/TaskManagerOG-[0-9]+\.[0-9]+\.[0-9]+-x86_64\.AppImage' "$ROOT_DIR/flake.nix" &&
	! rg -Fq 'builtins.fetchurl' "$PACKAGE"; then
	pass 'versioned official AppImage is locked without mutable version metadata'
else
	fail 'TMOG must use a versioned locked artifact, not mutable version.txt or impure evaluation'
fi

package_version="$(nix eval --raw "$ROOT_DIR#packages.x86_64-linux.tmog.version" 2>/dev/null)"
package_status=$?
if [ "$package_status" -eq 0 ] && [[ "$package_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	pass 'flake exposes an explicit semantic version'
else
	fail 'flake must expose packages.x86_64-linux.tmog at its locked semantic version'
fi

locked_url="$(jq -r '.nodes["tmog-linux"].locked.url' "$ROOT_DIR/flake.lock")"
locked_hash="$(jq -r '.nodes["tmog-linux"].locked.narHash' "$ROOT_DIR/flake.lock")"
if [ "$locked_url" = "https://tmog.org/rtm/downloads/TaskManagerOG-${package_version}-x86_64.AppImage" ] &&
	[[ "$locked_hash" == sha256-* ]] &&
	jq -e '.nodes | has("tmog-version") | not' "$ROOT_DIR/flake.lock" >/dev/null; then
	pass 'locked artifact version agrees with package version; obsolete metadata input removed'
else
	fail 'TMOG artifact, package version, and lock must remain consistent'
fi

check_name="$(nix eval --raw "$ROOT_DIR#checks.x86_64-linux.tmog.name" 2>/dev/null)"
check_status=$?
if [ "$check_status" -eq 0 ] && [ -n "$check_name" ]; then
	pass 'flake exposes a headless TMOG package smoke check'
else
	fail 'flake must expose checks.x86_64-linux.tmog'
fi

placement="$({
	nix eval --json "$ROOT_DIR#nixosConfigurations" --apply '
		configurations:
		let
			isTmog = package: (package.pname or "") == "tmog-task-manager";
			placement = host: user:
				let config = configurations.${host}.config;
				in {
					user = builtins.any isTmog config.users.users.${user}.packages;
					system = builtins.any isTmog config.environment.systemPackages;
				};
		in {
			thelio = placement "thelio-nixos" "pmarreck";
			framework = placement "framework-nixos" "pmarreck";
			tiki = placement "tiki-wsl-nixos" "nixos";
		}
	' 2>/dev/null
})"
placement_status=$?
expected='{"framework":{"system":false,"user":true},"thelio":{"system":false,"user":true},"tiki":{"system":false,"user":true}}'
if [ "$placement_status" -eq 0 ] && [ "$placement" = "$expected" ]; then
	pass 'all three Linux hosts install TMOG only for their active human user'
else
	fail 'Thelio, Framework, and Tiki-WSL must install TMOG in the intended user profile'
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
