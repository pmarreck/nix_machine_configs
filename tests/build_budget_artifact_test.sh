#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
artifact="${BUILD_BUDGET_ARTIFACT:-}"
if [[ -z "$artifact" ]]; then
	package=$(nix build "$root#build-resources" --no-link --print-out-paths 2>/dev/null) || { printf 'FAIL: build-budget artifact preparation\n' >&2; exit 1; }
	artifact="$package/bin/build-budget"
fi
fixture=$(mktemp -d) || exit 1
trap 'rm-safe -r -- "$fixture" >/dev/null' EXIT
mkdir -p "$fixture/home" "$fixture/runtime" "$fixture/state" "$fixture/tmp"
systemctl() {
	case "$*" in
		*'show agentbuilds.slice'*) printf '34359738368\n' ;;
		*is-active*) return 3 ;;
		*) printf 'success\n1\n' ;;
	esac
}
systemd-run() { printf '%s\0' "$@" > "$ARTIFACT_ARGS"; }
export -f systemctl systemd-run
HOME="$fixture/home" XDG_RUNTIME_DIR="$fixture/runtime" XDG_STATE_HOME="$fixture/state" TMPDIR="$fixture/tmp" ARTIFACT_ARGS="$fixture/args" \
	timeout --kill-after=1s 3s "$artifact" --project artifact -- true > "$fixture/out" 2> "$fixture/err"
status=$?
if [[ "$status" -ne 0 ]]; then
	printf 'FAIL: packaged interpreter cannot admit an isolated job (exit %s)\n' "$status" >&2
	head -n 5 "$fixture/err" >&2
	exit 1
fi
if [[ ! -f "$fixture/args" ]]; then printf 'FAIL: packaged command never reached the recording scope adapter\n' >&2; exit 1; fi
found=false
while IFS= read -r -d '' value; do [[ "$value" != --property=RuntimeMaxSec=1800 ]] || found=true; done < "$fixture/args"
if [[ "$found" != true ]]; then printf 'FAIL: packaged scope has no default runtime limit\n' >&2; exit 1; fi
if [[ $(jq -s 'length' "$fixture/state/build-budget/runs.ndjson") != 1 ]]; then printf 'FAIL: packaged command has no terminal receipt\n' >&2; exit 1; fi
printf 'build-budget actual executable/interpreter: PASS\n'
