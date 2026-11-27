#!/usr/bin/env bash
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/build-budget"
build_budget_priority_names() { printf '[]\n'; }
fixture=$(mktemp -d) || exit 1
export MECHATRON_ADMISSION_DIR="$fixture/admission"
mkdir -p "$MECHATRON_ADMISSION_DIR"
: > "$MECHATRON_ADMISSION_DIR/admission.lock"
children=()
cleanup() { local child; for child in "${children[@]}"; do kill -TERM "$child" 2>/dev/null; wait "$child" 2>/dev/null; done; command rm -rf -- "$fixture"; }
trap cleanup EXIT
failures=0
assert_eq() { if [[ "$1" != "$2" ]]; then printf 'FAIL: %s expected %s, got %s\n' "$3" "$1" "$2" >&2; failures=$((failures+1)); fi; }
if ! declare -F build_budget_register_ticket >/dev/null; then printf 'FAIL: FIFO admission is absent\n' >&2; exit 1; fi
chmod 0444 "$MECHATRON_ADMISSION_DIR/admission.lock"
admission_drain_lock shared_one shared; assert_eq 0 "$?" 'read-only client obtains shared drain lock'
admission_drain_lock shared_two shared; assert_eq 0 "$?" 'multiple readers share the drain lock'
if admission_drain_lock exclusive exclusive 2>/dev/null; then
	assert_eq 1 0 'read-only client cannot open an exclusive mutation lock'
else
	assert_eq 1 "$?" 'read-only client cannot open an exclusive mutation lock'
fi
exec {shared_one}<&-
exec {shared_two}<&-
chmod 0644 "$MECHATRON_ADMISSION_DIR/admission.lock"
mkdir "$fixture/runtime"
build_budget_register_ticket first "$fixture/runtime"
build_budget_register_ticket second "$fixture/runtime"
assert_eq 0 "$?" 'ticket registration'
set -f
build_budget_ticket_first "$first" "$fixture/runtime"
assert_eq 0 "$?" 'oldest is eligible'
set +f
build_budget_ticket_first "$second" "$fixture/runtime"
assert_eq 1 "$?" 'younger waits'
command unlink "$first"
build_budget_ticket_first "$second" "$fixture/runtime"
assert_eq 0 "$?" 'next waiter advances'
command unlink "$second"
# Dead and PID-reused owners cannot block a live waiter.
build_budget_register_ticket stale "$fixture/runtime"
printf '99999999 missing\n' > "$stale"
build_budget_register_ticket live "$fixture/runtime"
build_budget_ticket_first "$live" "$fixture/runtime"
assert_eq 0 "$?" 'dead owner pruned'
assert_eq false "$(test -e "$stale" && echo true || echo false)" 'dead ticket removed'
command unlink "$live"
# Priority is a stable class ahead of ordinary FIFO, and vanishes at expiry.
build_budget_register_ticket ordinary "$fixture/runtime" ordinary
build_budget_register_ticket priority "$fixture/runtime" media
build_budget_priority_names() { printf '["media"]\n'; }
build_budget_ticket_first "$priority" "$fixture/runtime"
assert_eq 0 "$?" 'priority overtakes queued ordinary work'
build_budget_ticket_first "$ordinary" "$fixture/runtime"
assert_eq 1 "$?" 'ordinary waits behind active priority class'
build_budget_priority_names() { printf '[]\n'; }
build_budget_ticket_first "$ordinary" "$fixture/runtime"
assert_eq 0 "$?" 'expiry restores original FIFO age'
command unlink "$ordinary"; command unlink "$priority"
# Explicit host registry approvals are required; environment defaults cannot
# extend main's selected bound. Classify malformed and unauthorized entries.
policy="$fixture/approvals.json"
assert_eq 1800 "$(build_budget_runtime_limit demo "$policy")" 'missing policy uses default'
for entry in \
	'{"seconds":3600,"approved_by":"mechatron-prime","reason":"approved case"}' \
	'{"seconds":3600,"approved_by":"project-agent","reason":"self approval"}' \
	'{"seconds":3600,"approved_by":"mechatron-prime","reason":""}' \
	'{"seconds":3600.5,"approved_by":"mechatron-prime","reason":"fractional"}' \
	'{"seconds":0,"approved_by":"mechatron-prime","reason":"zero"}' \
	'{"seconds":86401,"approved_by":"mechatron-prime","reason":"unbounded"}'; do
	jq -cn --argjson entry "$entry" '{schema:"mechatron-runtime-approvals/v1",approvals:{"local/demo":$entry}}' > "$policy"
	value=$(build_budget_runtime_limit demo "$policy"); status=$?
	if [[ "$entry" == *'approved case'* ]]; then assert_eq 3600 "$value" 'approved exception applied'
	else assert_eq 5 "$status" 'invalid exception rejected'; fi
done
build_budget_register_ticket stale "$fixture/runtime"
printf '%s wrong-birth\n' "$BASHPID" > "$stale"
build_budget_register_ticket live "$fixture/runtime"
build_budget_ticket_first "$live" "$fixture/runtime"
assert_eq 0 "$?" 'reused PID pruned'
command unlink "$live"
# Overlap two real callers. Inject only the blocking slot and wait ports;
# barriers prove the younger caller cannot enter slot acquisition first.
mkfifo "$fixture/events" "$fixture/old-release" "$fixture/young-release"
exec 6<> "$fixture/events"
exec 7<> "$fixture/old-release"
exec 8<> "$fixture/young-release"
build_budget_acquire_slot() {
	local -n output="$1"
	printf 'slot-%s\n' "$label" >&6
	exec {output}> "$fixture/lease-$label"
}
build_budget_wait() {
	printf 'wait-%s\n' "$label" >&6
	IFS= read -r _ < "$fixture/young-release"
}
run_waiter() (
	label="$1"
	build_budget_register_ticket ticket "$fixture/runtime" || exit 1
	if [[ "$label" == old ]]; then printf 'ticket-old\n' >&6; IFS= read -r _ < "$fixture/old-release"; fi
	build_budget_acquire_fair_slot lease "$fixture/runtime" "$ticket" || exit 1
	command unlink "$ticket"
)
run_waiter old & old_pid=$!
children+=("$old_pid")
IFS= read -r -t 10 event <&6 || exit 1
assert_eq ticket-old "$event" 'oldest registers first'
run_waiter young 2> "$fixture/young.err" & young_pid=$!
children+=("$young_pid")
IFS= read -r -t 10 event <&6 || exit 1
assert_eq wait-young "$event" 'newer caller waits behind oldest'
printf 'go\n' >&7
wait "$old_pid"; assert_eq 0 "$?" 'oldest completes admission'
children=("$young_pid")
IFS= read -r -t 10 event <&6 || exit 1
assert_eq slot-old "$event" 'oldest enters slot acquisition first'
printf 'go\n' >&8
IFS= read -r -t 10 event <&6 || exit 1
assert_eq slot-young "$event" 'younger advances after oldest'
wait "$young_pid"; assert_eq 0 "$?" 'younger completes admission'
children=()

# The host drain gates local slots as well as CI claims. A waiting local job
# retains its FIFO ticket and advances immediately at exact lease expiry.
build_budget_register_ticket drained "$fixture/runtime" demo
drain_ticket=$drained
printf '%s\n' '{"schema":"mechatron-admission-drain/v1","lease_id":"test-lease","owner":"owner","created_at":100,"expires_at":200}' > "$MECHATRON_ADMISSION_DIR/drain.json"
MECHATRON_NOW_EPOCH=150
local_slot_calls=0
build_budget_acquire_slot() { local -n output="$1"; local_slot_calls=$((local_slot_calls+1)); output=77; }
build_budget_wait() { assert_eq 0 "$local_slot_calls" 'local waiter does not enter while lease is active'; MECHATRON_NOW_EPOCH=200; }
build_budget_acquire_fair_slot local_lease "$fixture/runtime" "$drain_ticket"
assert_eq 0 "$?" 'local waiter proceeds after exact drain expiry'
assert_eq 1 "$local_slot_calls" 'local waiter does not touch a slot while drained'
assert_eq true "$(test -f "$drain_ticket" && echo true || echo false)" 'drain preserves the pre-existing FIFO ticket'
command unlink "$drain_ticket"
printf 'build-budget FIFO: %d failure(s)\n' "$failures"
exit "$failures"
