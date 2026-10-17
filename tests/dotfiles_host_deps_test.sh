#!/usr/bin/env bash

# ~/dotfiles syncs to every host, and its commands and host test suite call
# these tools from PATH, so each NixOS host must install them declaratively
# (not only inside the dotfiles flake shell).

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

missing="$({
	nix eval --json "$ROOT_DIR#nixosConfigurations" --apply '
		configurations:
		let
			# bin/repo-maintenance keys its state with b3sum digests.
			required = [ "b3sum" ];
			names = host: user:
				let config = configurations.${host}.config;
				in map (package: package.pname or "") (
					config.environment.systemPackages ++
					config.users.users.${user}.packages
				);
			missingOn = host: user:
				builtins.filter (name: !(builtins.elem name (names host user))) required;
		in {
			framework = missingOn "framework-nixos" "pmarreck";
			thelio = missingOn "thelio-nixos" "pmarreck";
			tiki = missingOn "tiki-wsl-nixos" "nixos";
		}
	' 2>/dev/null
})"
status=$?

if [ "$status" -eq 0 ]; then
	pass 'all declared NixOS host package sets evaluate'
else
	fail 'declared NixOS host package sets must evaluate'
fi

expected='{"framework":[],"thelio":[],"tiki":[]}'
if [ "$missing" = "$expected" ]; then
	pass 'every NixOS host installs the tools dotfiles needs'
else
	fail "dotfiles tools missing per host: [$missing]"
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
