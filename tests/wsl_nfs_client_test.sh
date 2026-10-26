#!/usr/bin/env bash

# Require the WSL host's NFS declaration to install a usable mount helper.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
HOST_ATTR="$ROOT_DIR#nixosConfigurations.tiki-wsl-nixos"
NFS_UTILS_ATTR="$HOST_ATTR.pkgs.nfs-utils"

failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

supported="$(nix eval --json "$HOST_ATTR.config.boot.supportedFilesystems" 2>/dev/null)"
supported_status=$?
if [ "$supported_status" -eq 0 ] && jq -e '.nfs == true' <<<"$supported" >/dev/null; then
	pass 'the WSL host declares NFS filesystem support'
else
	fail 'the WSL host must declare NFS filesystem support'
fi

packages="$(nix eval --json "$HOST_ATTR.config.system.fsPackages" \
	--apply 'builtins.map (package: package.pname or package.name or "")' 2>/dev/null)"
packages_status=$?
if [ "$packages_status" -eq 0 ] && jq -e 'index("nfs-utils") != null' <<<"$packages" >/dev/null; then
	pass 'the evaluated WSL system includes nfs-utils'
else
	fail 'the evaluated WSL system must include nfs-utils'
fi

nix build --no-link "$NFS_UTILS_ATTR" >/dev/null 2>&1
build_status=$?
nfs_utils_path="$(nix eval --raw "$NFS_UTILS_ATTR.outPath" 2>/dev/null)"
path_status=$?
if [ "$build_status" -eq 0 ] && [ "$path_status" -eq 0 ] &&
	[ -x "$nfs_utils_path/bin/mount.nfs" ]; then
	pass 'the locked nfs-utils package provides mount.nfs'
else
	fail 'the locked nfs-utils package must provide an executable mount.nfs'
fi

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
