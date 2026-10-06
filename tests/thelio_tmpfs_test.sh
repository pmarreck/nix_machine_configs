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
capture nix eval --json "path:$ROOT_DIR#nixosConfigurations.thelio-nixos.config" --apply 'c: { boot = c.boot.tmp; cleanup = c.systemd.services.tmp-cleanup.serviceConfig; timer = c.systemd.timers.tmp-cleanup.timerConfig; }'

if [ "$rc" -eq 0 ]; then
	pass 'effective Thelio boot.tmp configuration evaluates'
else
	fail "effective Thelio boot.tmp configuration must evaluate (exit $rc)"
fi

use_tmpfs="$(jq -r '.boot.useTmpfs // false' <<< "$out" 2>/dev/null)"
tmpfs_size="$(jq -r '.boot.tmpfsSize // ""' <<< "$out" 2>/dev/null)"
clean_on_boot="$(jq -r '.boot.cleanOnBoot // false' <<< "$out" 2>/dev/null)"

[ "$(jq -r '.timer.OnCalendar // ""' <<< "$out" 2>/dev/null)" = hourly ] \
	&& pass 'temporary cleanup runs hourly' || fail 'temporary cleanup must run hourly'
[ "$(jq -r '.timer.Persistent // false' <<< "$out" 2>/dev/null)" = true ] \
	&& pass 'missed cleanup runs after boot' || fail 'cleanup must be persistent'
[ "$(jq -r '.cleanup.RuntimeDirectory // ""' <<< "$out" 2>/dev/null)" = tmp-cleanup ] \
	&& pass 'cleanup metadata lives in runtime storage' || fail 'cleanup needs isolated runtime metadata'
[ "$(jq -r '.cleanup.StateDirectory // ""' <<< "$out" 2>/dev/null)" = '' ] \
	&& pass 'cleanup does not retain deleted content' || fail 'cleanup must not archive temporary content'

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
