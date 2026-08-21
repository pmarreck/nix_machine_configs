#!/usr/bin/env bash

# Effective Thelio contract for temporary storage. This evaluates the flake
# rather than grepping source, so an override elsewhere cannot silently move
# /tmp back onto the HDD-backed root pool.

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
capture nix eval --json "path:$ROOT_DIR#nixosConfigurations.thelio-nixos.config.boot.tmp"

if [ "$rc" -eq 0 ]; then
	pass 'effective Thelio boot.tmp configuration evaluates'
else
	fail "effective Thelio boot.tmp configuration must evaluate (exit $rc)"
fi

use_tmpfs="$(jq -r '.useTmpfs // false' <<< "$out" 2>/dev/null)"
tmpfs_size="$(jq -r '.tmpfsSize // ""' <<< "$out" 2>/dev/null)"
clean_on_boot="$(jq -r '.cleanOnBoot // false' <<< "$out" 2>/dev/null)"

[ "$use_tmpfs" = true ] \
	&& pass 'Thelio mounts /tmp as tmpfs' \
	|| fail 'Thelio must mount /tmp as tmpfs'

[ "$tmpfs_size" = '20%' ] \
	&& pass 'Thelio tmpfs retains its deliberate 20 percent ceiling' \
	|| fail "Thelio tmpfs ceiling must be 20 percent, got '$tmpfs_size'"

[ "$clean_on_boot" = true ] \
	&& pass 'Thelio temporary storage is cleaned on boot' \
	|| fail 'Thelio temporary storage must be cleaned on boot'

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
