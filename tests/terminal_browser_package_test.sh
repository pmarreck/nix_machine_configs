#!/usr/bin/env bash

# Contract for the standalone Nix-managed Terminal Browser package.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PACKAGE="$ROOT_DIR/packages/terminal-browser.nix"

failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

if [ -f "$PACKAGE" ] &&
	rg -Fq 'terminal-browser-linux-x64.tar.gz' "$PACKAGE" &&
	rg -Fq 'sha256-wzC+M0Hvb2yxBuT7MsHWB1Sgjhp2QRQ6empNnpRI9hc=' "$PACKAGE" &&
	! rg -Fq 'terminal-browser.sh/install |' "$PACKAGE"; then
	pass 'package pins the official Terminal Browser release and published hash'
else
	fail 'package must pin the official release asset without executing its installer'
fi

if [ -f "$PACKAGE" ] &&
	rg -Fq 'managed by Nix; update /etc/nixos instead' "$PACKAGE"; then
	pass 'mutable upstream self-upgrade is refused with Nix-specific guidance'
else
	fail 'package must refuse the curl-to-shell self-upgrade path'
fi

package_version="$(nix eval --raw "$ROOT_DIR#packages.x86_64-linux.terminal-browser.version" 2>/dev/null)"
package_status=$?
if [ "$package_status" -eq 0 ] && [ "$package_version" = '0.5.8' ]; then
	pass 'flake exposes Terminal Browser 0.5.8'
else
	fail 'flake must expose packages.x86_64-linux.terminal-browser at version 0.5.8'
fi

check_name="$(nix eval --raw "$ROOT_DIR#checks.x86_64-linux.terminal-browser.name" 2>/dev/null)"
check_status=$?
if [ "$check_status" -eq 0 ] && [ -n "$check_name" ]; then
	pass 'flake exposes an executable Terminal Browser smoke check'
else
	fail 'flake must expose checks.x86_64-linux.terminal-browser'
fi

placement="$({
	nix eval --raw \
		"$ROOT_DIR#nixosConfigurations.thelio-nixos.config" \
		--apply '
			config:
			let
				isTerminalBrowser = package: (package.pname or "") == "terminal-browser";
				inUserPackages = builtins.any isTerminalBrowser config.users.users.pmarreck.packages;
				inSystemPackages = builtins.any isTerminalBrowser config.environment.systemPackages;
			in
				if inUserPackages && !inSystemPackages then "user-only" else "incorrect"
		' 2>/dev/null
})"
placement_status=$?
if [ "$placement_status" -eq 0 ] && [ "$placement" = 'user-only' ]; then
	pass 'Thelio installs Terminal Browser for Peter without making it system-wide'
else
	fail 'Thelio must install Terminal Browser only in users.users.pmarreck.packages'
fi

if [ -f "$PACKAGE" ] &&
	rg -Fq 'TERMINAL_BROWSER_DIST_ROOT' "$PACKAGE" &&
	rg -Fq 'buildFHSEnv' "$PACKAGE"; then
	pass 'launcher retains its immutable distribution root inside a declared FHS runtime'
else
	fail 'package must preserve the bundled runtime layout inside an FHS environment'
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
