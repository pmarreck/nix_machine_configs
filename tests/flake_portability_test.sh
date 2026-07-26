#!/usr/bin/env bash

# Proves `bin/check-flake-portability` classifies flake inputs as portable vs
# machine-local, which is what stops a `path:/home/...` input from being pushed
# into a fleet-shared flake and breaking every OTHER machine's `nix flake update`.
#
# Peter's rule: no `set -e`/`-o pipefail` in test scripts — errexit aborts on the
# expected non-zero exits of the command under test. `set -u` only; the pass/fail
# helpers assert exit codes explicitly.
#
# The central case is a SET partition, not a single example: a filter must be
# tested as a classifier over a mixed set, so an over-broad rule that condemns
# every `path:` input (relative in-repo ones are perfectly portable) fails here.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECKER="$ROOT_DIR/bin/check-flake-portability"

failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

# Build a throwaway flake dir. $1 = flake.nix body, $2 = flake.lock body ("" = omit lock)
make_flake() {
	local dir
	dir="$(mktemp -d "${TMPDIR:-/tmp}/flakeport.XXXXXX")"
	printf '%s\n' "$1" > "$dir/flake.nix"
	[ -n "$2" ] && printf '%s\n' "$2" > "$dir/flake.lock"
	printf '%s' "$dir"
}

CLEAN_NIX='{ inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; outputs = { ... }: { }; }'

# ---------------------------------------------------------------------------
# 1. SET PARTITION — the load-bearing test.
#    5 inputs: 2 genuinely non-portable, 3 portable (one of which is a RELATIVE
#    path input, the trap for a naive "does it contain path:" substring rule).
# ---------------------------------------------------------------------------
mixed_lock='{
  "version": 7,
  "root": "root",
  "nodes": {
    "root": { "inputs": { "nixpkgs": "nixpkgs", "hw": "hw", "localmod": "localmod", "ollama": "ollama", "vendored": "vendored" } },
    "nixpkgs":  { "locked": { "type": "github", "owner": "NixOS", "repo": "nixpkgs", "rev": "aaaa" } },
    "hw":       { "locked": { "type": "github", "owner": "NixOS", "repo": "nixos-hardware", "rev": "bbbb" } },
    "localmod": { "locked": { "type": "path", "path": "./modules/localmod" } },
    "ollama":   { "locked": { "type": "path", "path": "/home/pmarreck/Code/ollama" } },
    "vendored": { "locked": { "type": "git", "url": "file:///home/pmarreck/Code/vendored" } }
  }
}'
dir="$(make_flake "$CLEAN_NIX" "$mixed_lock")"
out="$("$CHECKER" "$dir" 2>&1)"; rc=$?

[ "$rc" -ne 0 ] && pass 'mixed set: exits non-zero when any input is machine-local' \
                || fail "mixed set: expected non-zero exit, got $rc"

# names exactly the two offenders...
case "$out" in *ollama*)   pass 'mixed set: flags the absolute path: input (ollama)' ;;
                        *) fail "mixed set: did not flag ollama (got: $out)" ;; esac
case "$out" in *vendored*) pass 'mixed set: flags the git+file:// input (vendored)' ;;
                        *) fail "mixed set: did not flag vendored (got: $out)" ;; esac

# ...and condemns none of the three portable ones.
for ok_input in nixpkgs hw localmod; do
	case "$out" in
		*"$ok_input"*) fail "mixed set: false positive on portable input '$ok_input' (got: $out)" ;;
		*)             pass "mixed set: does not flag portable input '$ok_input'" ;;
	esac
done
rm -rf "$dir"

# ---------------------------------------------------------------------------
# 2. An all-portable flake must be silent and succeed (no vacuous green: the
#    checker must be capable of passing, or test 1 proves nothing).
# ---------------------------------------------------------------------------
clean_lock='{
  "version": 7, "root": "root",
  "nodes": {
    "root": { "inputs": { "nixpkgs": "nixpkgs" } },
    "nixpkgs": { "locked": { "type": "github", "owner": "NixOS", "repo": "nixpkgs", "rev": "cccc" } }
  }
}'
dir="$(make_flake "$CLEAN_NIX" "$clean_lock")"
out="$("$CHECKER" "$dir" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass 'clean flake: exits zero' || fail "clean flake: expected 0, got $rc ($out)"
rm -rf "$dir"

# ---------------------------------------------------------------------------
# 3. Caught in flake.nix even with NO lock yet — the violation is introduced
#    when the input is written, not when it is locked.
# ---------------------------------------------------------------------------
bad_nix='{ inputs.ollama.url = "path:/home/pmarreck/Code/ollama"; outputs = { ... }: { }; }'
dir="$(make_flake "$bad_nix" "")"
out="$("$CHECKER" "$dir" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && pass 'unlocked flake.nix: absolute path: input still caught' \
                || fail "unlocked flake.nix: expected non-zero, got $rc ($out)"
rm -rf "$dir"

# ---------------------------------------------------------------------------
# 4. --warn is advisory: it must still REPORT, but must not block (pre-commit).
# ---------------------------------------------------------------------------
dir="$(make_flake "$bad_nix" "")"
out="$("$CHECKER" --warn "$dir" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass '--warn: exits zero (never blocks a commit)' \
                || fail "--warn: expected 0, got $rc"
case "$out" in *ollama*) pass '--warn: still reports the offending input' ;;
                      *) fail "--warn: reported nothing (got: $out)" ;; esac
rm -rf "$dir"

# ---------------------------------------------------------------------------
# 5. A relative path input alone must NOT trip the gate (anti-overreach).
# ---------------------------------------------------------------------------
rel_nix='{ inputs.localmod.url = "path:./modules/localmod"; outputs = { ... }: { }; }'
dir="$(make_flake "$rel_nix" "")"
out="$("$CHECKER" "$dir" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass 'relative in-repo path: input is allowed' \
                || fail "relative path: expected 0, got $rc ($out)"
rm -rf "$dir"

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
