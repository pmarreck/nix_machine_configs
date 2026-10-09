#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$HOME/dotfiles/bin/src/capture.bash"
failures=0
checks=0
assert() {
	checks=$((checks + 1))
	if ! "$@"; then printf 'not ok - %s\n' "$*" >&2; failures=$((failures + 1)); fi
}
if [[ ! -f "$root/scripts/build-budget" || ! -f "$root/scripts/build-oom-watch" ]]; then
	printf 'not ok - build resource implementation missing\n' >&2
	exit 1
fi
source "$root/scripts/build-budget"
source "$root/scripts/build-oom-watch"

# Project labels form a classifier over accepted and rejected input sets.
for project in validate validate_gui a-b foo123; do assert build_budget_valid_project "$project"; done
for project in '' '../bad' 'two words' '-flag' 'a/b' $'a\nb'; do
	if build_budget_valid_project "$project"; then assert false; else assert true; fi
done
args=()
build_budget_args args validate unit-id '/work/a b' bash -c 'exit 7'
assert test "${args[0]}" = '--user'
assert test "${args[3]}" = '--slice=agentbuilds.slice'
assert test "${args[4]}" = '--unit=build-validate-unit-id.scope'
assert test "${args[5]}" = '--working-directory=/work/a b'
assert test "${args[6]}" = '--property=MemoryHigh=12G'
assert test "${args[7]}" = '--property=MemoryMax=16G'
assert test "${args[8]}" = '--property=MemorySwapMax=0'
assert test "${args[9]}" = '--property=OOMPolicy=stop'
assert test "${args[10]}" = '--'
assert test "${args[13]}" = 'exit 7'
out='' err='' rc=0
capture build_budget_main --project '../bad' -- true
assert test "$rc" -eq 2
capture build_budget_main --project validate
assert test "$rc" -eq 2
capture build_budget_main --help
assert test "$rc" -eq 0
assert test "${out#*build-budget}" != "$out"

message='oom-kill:constraint=CONSTRAINT_MEMCG,nodemask=(null),cpuset=build-validate-123.scope,mems_allowed=0,oom_memcg=/user.slice/user-1000.slice/user@1000.service/agentbuilds.slice/build-validate-123.scope,task_memcg=/user.slice/user-1000.slice/user@1000.service/agentbuilds.slice/build-validate-123.scope,task=test,pid=42,uid=1000'
capture build_oom_record "$message" '2026-10-09T23:00:00Z' 17179869184 17179869184
assert test "$rc" -eq 0
assert test "$(jq -r '.classification' <<< "$out")" = 'job-limit'
assert test "$(jq -r '.unit' <<< "$out")" = 'build-validate-123.scope'
assert test "$(jq -r '.project' <<< "$out")" = 'validate'
assert test "$(jq -r '.pid' <<< "$out")" = '42'
assert test "$(jq -r '.peak_bytes' <<< "$out")" = '17179869184'
assert test "$(jq -r '.datetime' <<< "$out")" = '2026-10-09T23:00:00Z'
uuid_message=${message//build-validate-123.scope/build-validate_gui-295d25a8-cd52-4749-abb1-ef152074d4b8.scope}
capture build_oom_record "$uuid_message" now 42 99
assert test "$rc" -eq 0
assert test "$(jq -r '.project' <<< "$out")" = 'validate_gui'
aggregate_message=${message/oom_memcg=\/user.slice\/user-1000.slice\/user@1000.service\/agentbuilds.slice\/build-validate-123.scope,/oom_memcg=\/user.slice\/user-1000.slice\/user@1000.service\/agentbuilds.slice,}
capture build_oom_record "$aggregate_message" now 42 99
assert test "$rc" -eq 0
assert test "$(jq -r '.limit_cgroup' <<< "$out")" = '/user.slice/user-1000.slice/user@1000.service/agentbuilds.slice'
assert test "$(jq -r '.cgroup' <<< "$out")" = '/user.slice/user-1000.slice/user@1000.service/agentbuilds.slice/build-validate-123.scope'
global_message='oom-kill:constraint=CONSTRAINT_NONE,nodemask=(null),cpuset=/,mems_allowed=0,global_oom,task_memcg=/system.slice/example.service,task=worker,pid=99,uid=1000'
capture build_oom_record "$global_message" now '' max
assert test "$rc" -eq 0
assert test "$(jq -r '.classification' <<< "$out")" = 'host-oom'
assert test "$(jq -r '.limit_bytes' <<< "$out")" = 'null'
assert test "$(jq -r '.project' <<< "$out")" = 'null'
assert test "$(jq -r '.unit' <<< "$out")" = 'example.service'
assert test "$(jq -r '.limit_cgroup' <<< "$out")" = 'null'
capture build_oom_record 'unrelated message' now '' ''
assert test "$rc" -ne 0

# A FUSE mount refusing metadata must not abort the top-level cleanup inventory.
source "$root/scripts/tmp-cleanup"
fixture=$(mktemp -d) || exit 1
trap 'rm-safe -r -- "$fixture" >/dev/null' EXIT
mkdir -p "$fixture/tmp/mounted" "$fixture/proc/self" "$fixture/work"
printf '1 0 0:1 / %s rw - fuse fuse rw\n' "$fixture/tmp/mounted" > "$fixture/proc/self/mountinfo"
printf 'keep\n' > "$fixture/tmp/mounted/content"
printf 'stale\n' > "$fixture/tmp/.hidden-stale"
find() {
	if [[ "$1" == "$fixture/tmp" ]]; then printf 'fixture: FUSE metadata denied\n' >&2; return 1; fi
	command find "$@"
}
capture tmp_cleanup_run "$fixture/tmp" "$fixture/proc" "$fixture/work" 10000000000 dry-run
assert test "$rc" -eq 0
assert test -f "$fixture/tmp/.hidden-stale"
assert test -f "$fixture/tmp/mounted/content"
assert test "$err" = ''
assert test "${out#*removed=1}" != "$out"
unset -f find

# Real CLI composition with a recording systemd adapter: status, receipts and
# task-owned scratch retention/cleanup, without launching another build.
systemctl() {
	case "$*" in
		*'show agentbuilds.slice -p MemoryMax'*) printf '%s\n' "$adapter_envelope" ;;
		*'is-active'*) return 3 ;;
		*) printf 'success\n1234\n' ;;
	esac
}
systemd-run() {
	local argument
	printf '%s\0' "$@" > "$fixture/requested-arguments"
	for argument in "$@"; do
		if [[ "$argument" == TMPDIR=* ]]; then printf '%s\n' "${argument#TMPDIR=}" > "$fixture/scratch-path"; fi
	done
	return "$adapter_status"
}
export XDG_RUNTIME_DIR="$fixture/runtime"
export XDG_STATE_HOME="$fixture/state"
export TMPDIR="$fixture/tmp"
adapter_envelope=infinity
adapter_status=0
capture build_budget_main --project validate -- true
assert test "$rc" -eq 1
assert test ! -e "$fixture/requested-arguments"
assert test ! -e "$fixture/state/build-budget/runs.ndjson"
adapter_envelope=34359738368
adapter_status=7
capture build_budget_main --project validate -- bash -c 'exit 7'
assert test "$rc" -eq 7
scratch=$(< "$fixture/scratch-path")
assert test -d "$scratch"
assert test "$(jq -s '.[0].exit_code' "$fixture/state/build-budget/runs.ndjson")" = 7
assert test "$(jq -s '.[0].peak_bytes' "$fixture/state/build-budget/runs.ndjson")" = 1234
adapter_status=0
capture build_budget_main --project validate -- true
assert test "$rc" -eq 0
scratch=$(< "$fixture/scratch-path")
assert test ! -e "$scratch"
assert test "$(jq -s 'length' "$fixture/state/build-budget/runs.ndjson")" = 2
unset -f systemctl systemd-run
printf 'build resources: %d checks, %d failure(s)\n' "$checks" "$failures"
exit "$failures"
