#!/usr/bin/env bash

# Effective Thelio contract for the Mechatron orchestration worker. Nix flake
# evaluation runs in this cgroup even though builders run under nix-daemon, so
# an undersized worker limit converts a few GiB of evaluator memory into heavy
# swap I/O on the HDD-backed root pool.

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
capture nix eval --json \
	"path:$ROOT_DIR#nixosConfigurations.thelio-nixos.config.systemd.services.mechatron-prime-worker.serviceConfig"

if [ "$rc" -eq 0 ]; then
	pass 'effective Mechatron worker service configuration evaluates'
else
	fail "effective Mechatron worker service configuration must evaluate (exit $rc)"
fi

memory_high="$(jq -r '.MemoryHigh // ""' <<< "$out" 2>/dev/null)"
memory_max="$(jq -r '.MemoryMax // ""' <<< "$out" 2>/dev/null)"
memory_swap_max="$(jq -r '.MemorySwapMax // ""' <<< "$out" 2>/dev/null)"

[ "$memory_high" = '8G' ] \
	&& pass 'Mechatron evaluator gets an 8 GiB unthrottled working set' \
	|| fail "Mechatron MemoryHigh must be 8G, got '$memory_high'"

[ "$memory_max" = '12G' ] \
	&& pass 'Mechatron evaluator has a bounded 12 GiB hard ceiling' \
	|| fail "Mechatron MemoryMax must be 12G, got '$memory_max'"

[ "$memory_swap_max" = '1G' ] \
	&& pass 'Mechatron cannot silently churn unlimited HDD-backed swap' \
	|| fail "Mechatron MemorySwapMax must be 1G, got '$memory_swap_max'"

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
