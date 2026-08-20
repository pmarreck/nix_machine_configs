#!/usr/bin/env bash

# Contract for the Nix-managed Terminal Code package and its host placement.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PACKAGE="$ROOT_DIR/packages/tode.nix"

failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

if [ -f "$PACKAGE" ] &&
	rg -Fq 'tode-linux-x64.tar.gz' "$PACKAGE" &&
	rg -Fq 'sha256-zMKgw6nCV/xCztd+bxtM5SugzBxFKaYB9lV6Uku00XM=' "$PACKAGE" &&
	! rg -Fq 'tode.sh/install' "$PACKAGE"; then
	pass 'package pins the official Terminal Code release asset and hash'
else
	fail 'package must pin the official Terminal Code release asset without running its installer'
fi

if [ -f "$PACKAGE" ] &&
	rg -Fq 'code-server-4.132.0-linux-amd64.tar.gz' "$PACKAGE" &&
	rg -Fq 'sha256-o40m9MuB92j+3f954pN/0/Ocg9Pai+PaciXhCH5i5O0=' "$PACKAGE"; then
	pass 'package pins the exact code-server runtime Terminal Code expects'
else
	fail 'package must pin code-server 4.132.0 and its published hash'
fi

package_version="$(nix eval --raw "$ROOT_DIR#packages.x86_64-linux.tode.version" 2>/dev/null)"
package_status=$?
if [ "$package_status" -eq 0 ] && [ "$package_version" = '0.1.13' ]; then
	pass 'flake exposes Terminal Code 0.1.13 as tode'
else
	fail 'flake must expose packages.x86_64-linux.tode at version 0.1.13'
fi

check_name="$(nix eval --raw "$ROOT_DIR#checks.x86_64-linux.tode.name" 2>/dev/null)"
check_status=$?
if [ "$check_status" -eq 0 ] && [ -n "$check_name" ]; then
	pass 'flake exposes an executable Terminal Code smoke check'
else
	fail 'flake must expose checks.x86_64-linux.tode'
fi

placement="$(
	nix eval --raw \
		"$ROOT_DIR#nixosConfigurations.thelio-nixos.config" \
		--apply '
			config:
			let
				isTode = package: (package.pname or "") == "tode";
				inUserPackages = builtins.any isTode config.users.users.pmarreck.packages;
				inSystemPackages = builtins.any isTode config.environment.systemPackages;
			in
				if inUserPackages && !inSystemPackages then "user-only" else "incorrect"
		' 2>/dev/null
)"
placement_status=$?
if [ "$placement_status" -eq 0 ] && [ "$placement" = 'user-only' ]; then
	pass 'Thelio installs tode for Peter without making it system-wide'
else
	fail 'Thelio must install tode only in users.users.pmarreck.packages'
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
