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

if rg -Fq 'file+https://tmog.org/downloads/release-linux.json' "$ROOT_DIR/flake.nix" &&
	rg -Fq 'inherit (tmogRelease) url sha256;' "$ROOT_DIR/flake.nix" &&
	! rg -Fq 'builtins.fetchurl' "$PACKAGE"; then
	pass 'Linux version, versioned artifact and checksum come from one locked manifest'
else
	fail 'TMOG must use the Linux manifest, not the cross-platform version or stale legacy AppImage'
fi

# The parser is a local test fixture, not a flake input for this pure-data check.
release_contract="$(nix eval --impure --json --expr '
  let
    parse = import '"$ROOT_DIR"'/packages/tmog-release.nix;
    good = { schemaVersion = 1; platform = "Linux"; architecture = "x86_64";
      version = "0.1.4"; artifact = "/downloads/TaskManagerOG-0.1.4-x86_64.AppImage";
      sha256 = "a9873347ee2b1a4895cf2c8f39660d8cf4b86ab89b24c08d541f237e365b4346"; };
    rejects = change: !(builtins.tryEval
      (builtins.deepSeq (parse { manifest = good // change; }) true)).success;
  in {
    valid = (parse { manifest = good; }).url ==
      "https://tmog.org/downloads/TaskManagerOG-0.1.4-x86_64.AppImage";
    wrongPlatform = rejects { platform = "Windows"; };
    wrongArch = rejects { architecture = "aarch64"; };
    wrongSchema = rejects { schemaVersion = 2; };
    mismatchedVersion = rejects { version = "0.1.5"; };
    externalURL = rejects { artifact = "https://example.com/evil.AppImage"; };
    missingHash = rejects { sha256 = ""; };
  }
' 2>/dev/null)"
release_status=$?
if [ "$release_status" -eq 0 ] &&
  printf '%s' "$release_contract" | jq -e 'length == 7 and all(.[]; . == true)' >/dev/null; then
  pass 'release manifest accepts Linux x86_64 and rejects wrong identity/version/URL/hash'
else
  fail 'release manifest validation must reject cross-platform or inconsistent metadata'
fi

package_version="$(nix eval --raw "$ROOT_DIR#packages.x86_64-linux.tmog.version" 2>/dev/null)"
package_status=$?
if [ "$package_status" -eq 0 ] && [[ "$package_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	pass 'flake exposes a semantic version from the locked official endpoint'
else
	fail 'flake must expose packages.x86_64-linux.tmog at its locked semantic version'
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
