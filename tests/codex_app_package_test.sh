#!/usr/bin/env bash

# Contract for the official Codex Linux GUI package without activating it.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PACKAGE="$ROOT_DIR/packages/codex-app.nix"

failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

if [ -f "$PACKAGE" ] &&
	rg -Fq 'chatgpt_26.810.41047_amd64.deb' "$PACKAGE" &&
	rg -Fq 'sha256-eHFfo80Tb/ZwcNqnaBmtrsxbQumYUVWWWWRdzh+/KvM=' "$PACKAGE" &&
	! rg -Fq '/latest/' "$PACKAGE"; then
	pass 'package pins the versioned official artifact and exact content hash'
else
	fail 'package must pin the versioned official artifact and exact content hash'
fi

if [ -f "$PACKAGE" ] &&
	rg -Fq 'dpkg-deb -x' "$PACKAGE" &&
	! rg -q '/etc/apt|DEBIAN/(postinst|prerm|postrm)' "$PACKAGE"; then
	pass 'package extracts payload files without running vendor maintainer scripts'
else
	fail 'package must extract payload files without running vendor maintainer scripts'
fi

if [ -f "$PACKAGE" ] && ! rg -q 'xorg\.' "$PACKAGE"; then
	pass 'package uses current flat X11 package names without evaluation warnings'
else
	fail 'package must use current flat X11 package names without evaluation warnings'
fi

package_name="$(nix eval --raw "$ROOT_DIR#packages.x86_64-linux.codex-app.pname" 2>/dev/null)"
package_status=$?
if [ "$package_status" -eq 0 ] && [ "$package_name" = 'codex-app' ]; then
	pass 'flake exposes the standalone codex-app package'
else
	fail 'flake must expose the standalone codex-app package'
fi

check_name="$(nix eval --raw "$ROOT_DIR#checks.x86_64-linux.codex-app.name" 2>/dev/null)"
check_status=$?
if [ "$check_status" -eq 0 ] && [ -n "$check_name" ]; then
	pass 'flake exposes a codex-app package check'
else
	fail 'flake must expose a codex-app package check'
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
