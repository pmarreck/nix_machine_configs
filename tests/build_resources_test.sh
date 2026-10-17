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
# The same controls can verify the immutable executable before/after handover.
source "${BUILD_BUDGET_IMPLEMENTATION:-$root/scripts/build-budget}"
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
		*'is-active'*) return "${adapter_active_status:-3}" ;;
		*) printf 'success\n1234\n' ;;
	esac
}
systemd-run() {
	local argument
	printf '%s\0' "$@" > "$fixture/requested-arguments"
	if [[ "${adapter_check_slot_fd:-0}" -eq 1 ]]; then
		if [[ -e "/proc/$BASHPID/fd/$slot_fd" ]]; then return 76; fi
		# An actual child must inherit no reservation, including a descriptor
		# Bash might save temporarily while applying a command redirection.
		bash -c 'for fd in /proc/$$/fd/*; do case "$(readlink "$fd")" in */slot-1.lock|*/slot-2.lock) exit 76 ;; esac; done' || return 76
		if command flock -n "$XDG_RUNTIME_DIR/build-budget/slot-1.lock" true; then return 77; fi
		printf 'child-slot-fds=none parent-reservation=held\n' > "$fixture/slot-custody"
	fi
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

# Admission is a state-transition classifier, not a timed race. The recording
# lock adapter releases slot1 on the bounded slot2 wait's timeout. Retrying1
# must admit the job; permanent lock errors and cancellation must not spin.
flock() {
	local path slot
	path=$(readlink "/proc/$BASHPID/fd/${!#}")
	case "$path" in
		*/slot-1.lock|*/slot-2.lock) ;;
		*) command flock "$@"; return $? ;;
	esac
	slot=${path##*/}
	slot_calls=$((slot_calls + 1))
	printf '%s %s\n' "$*" "$slot" >> "$fixture/slot-effects"
	if [[ $slot_calls -gt 9 ]]; then return 76; fi
	case "$slot_case:$slot_calls" in
		free-one:1) return 0 ;;
		free-two:1|release-two:1) return 75 ;;
		free-two:2|release-two:2) return 0 ;;
		release-one:1|release-one:2) return 75 ;;
		release-one:3) [[ "$slot" == slot-1.lock ]] && return 0; return 75 ;;
		three-intervals:1|three-intervals:2|three-intervals:3|three-intervals:4|three-intervals:5|three-intervals:6) return 75 ;;
		three-intervals:7) return 0 ;;
		wait-error:1|wait-cancel:1|wait-interrupt:1) return 75 ;;
		wait-error:2|nonblock-error:1) return 74 ;;
		wait-cancel:2) kill -TERM "$BASHPID"; return 76 ;;
		wait-interrupt:2) kill -INT "$BASHPID"; return 76 ;;
		*) return 76 ;;
	esac
}
for slot_case in free-one free-two release-one release-two three-intervals wait-error wait-cancel wait-interrupt nonblock-error; do
	slot_calls=0
	# A unique adapter side-effect path proves whether a job was admitted.
	fixture_previous="$fixture"
	fixture="$fixture_previous/$slot_case"
	mkdir -p "$fixture"
	: > "$fixture/slot-effects"
	capture build_budget_main --project validate -- true
	case "$slot_case" in
		wait-error|nonblock-error) expected_status=74 ;;
		wait-cancel) expected_status=143 ;;
		wait-interrupt) expected_status=130 ;;
		*) expected_status=0 ;;
	esac
	assert test "$rc" -eq "$expected_status"
	if [[ "$expected_status" -eq 0 ]]; then
		assert test -f "$fixture/requested-arguments"
		case "$slot_case" in free-two|release-two) expected_slot='slot-2.lock' ;; *) expected_slot='slot-1.lock' ;; esac
		assert test "$(tail -n 1 "$fixture/slot-effects" | awk '{print $NF}')" = "$expected_slot"
	else
		assert test ! -e "$fixture/requested-arguments"
	fi
	if [[ "$slot_case" == release-one ]]; then
		assert test "$(wc -l < "$fixture/slot-effects")" -eq 3
		assert test "$(sed -n '2p' "$fixture/slot-effects" | cut -d' ' -f1-4)" = '-w 1 -E 75'
	fi
	fixture="$fixture_previous"
done
unset -f flock

# Real private-FD integration: close the reservation only in the command's
# environment. The wrapper must retain it through the call, while a launched
# descendant must not keep it alive after the wrapper completes.
adapter_check_slot_fd=1
capture build_budget_main --project validate -- true
assert test "$rc" -eq 0
adapter_check_slot_fd=0
assert test "$(cat "$fixture/slot-custody")" = 'child-slot-fds=none parent-reservation=held'
assert flock -n "$XDG_RUNTIME_DIR/build-budget/slot-1.lock" true
assert flock -n "$XDG_RUNTIME_DIR/build-budget/slot-2.lock" true

# Raw-source callers can inherit a guarded rm on PATH. Test the real removal
# effect, separately from the recording adapter used for the boundary set.
mkdir "$fixture/guard-bin"
printf '#!%s\n' "$(command -v bash)" > "$fixture/guard-bin/rm"
printf '%s\n' 'printf called >> "$GUARD_CALLS"' 'exit 64' >> "$fixture/guard-bin/rm"
chmod +x "$fixture/guard-bin/rm"
export GUARD_CALLS="$fixture/guard-calls"
export PATH="$fixture/guard-bin:$PATH"
capture build_budget_main --project validate -- true
assert test "$rc" -eq 0
scratch=$(< "$fixture/scratch-path")
assert test ! -e "$scratch"
assert test ! -e "$GUARD_CALLS"

# Classify the whole scratch-boundary set through recorded deletion requests.
printf '#!%s\n' "$(command -v bash)" > "$fixture/delete-adapter"
printf '%s\n' 'printf "%s\0" "$@" >> "$DELETE_RECORD"' 'exit "${DELETE_STATUS:-0}"' >> "$fixture/delete-adapter"
chmod +x "$fixture/delete-adapter"
export BUILD_BUDGET_RM="$fixture/delete-adapter" DELETE_RECORD="$fixture/deletions"
export TMPDIR="$fixture/tmp with spaces"
mkdir -p "$TMPDIR" "$fixture/outside"
mktemp() { printf '%s\n' "$controlled_scratch"; }
for boundary in valid wrong-project wrong-base symlink file missing failed active adapter-error; do
	controlled_scratch="$TMPDIR/build-validate.$boundary"
	adapter_status=0; adapter_active_status=3; DELETE_STATUS=0
	case "$boundary" in
		wrong-project) controlled_scratch="$TMPDIR/build-other.example"; mkdir "$controlled_scratch" ;;
		wrong-base) controlled_scratch="$fixture/outside/build-validate.example"; mkdir "$controlled_scratch" ;;
		symlink) ln -s "$fixture/outside" "$controlled_scratch" ;;
		file) touch "$controlled_scratch" ;;
		missing) : ;;
		failed) mkdir "$controlled_scratch"; adapter_status=7 ;;
		active) mkdir "$controlled_scratch"; adapter_active_status=0 ;;
		adapter-error) mkdir "$controlled_scratch"; DELETE_STATUS=71 ;;
		*) mkdir "$controlled_scratch" ;;
	esac
	export DELETE_STATUS
	: > "$DELETE_RECORD"
	capture build_budget_main --project validate -- true
	assert test "$rc" -eq "$adapter_status"
	if [[ "$boundary" == valid || "$boundary" == adapter-error ]]; then
		mapfile -d '' -t requested_delete < "$DELETE_RECORD"
		assert test "${#requested_delete[@]}" -eq 5
		assert test "${requested_delete[0]-}" = '-r'
		assert test "${requested_delete[1]-}" = '--one-file-system'
		assert test "${requested_delete[2]-}" = '--preserve-root=all'
		assert test "${requested_delete[3]-}" = '--'
		assert test "${requested_delete[4]-}" = "$controlled_scratch"
	else
		assert test ! -s "$DELETE_RECORD"
	fi
	if [[ "$boundary" == adapter-error ]]; then
		assert test -d "$controlled_scratch"
		assert test "${err#*scratch cleanup failed}" != "$err"
	fi
done
unset -f mktemp
adapter_status=0; adapter_active_status=3
: > "$fixture/requested-arguments"
BUILD_BUDGET_RM=rm capture build_budget_main --project validate -- true
assert test "$rc" -eq 1
assert test ! -s "$fixture/requested-arguments"
unset -f systemctl systemd-run
printf 'build resources: %d checks, %d failure(s)\n' "$checks" "$failures"
exit "$failures"
