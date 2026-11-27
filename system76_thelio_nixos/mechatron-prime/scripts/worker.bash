#!/usr/bin/env bash
# Sequentially drain the one global queue through owner and manifest policies.
set -u
set +e

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -F repo_is_owned_by >/dev/null; then
	# Deployment may override the packaged library path.
	# shellcheck disable=SC1090
	source "${MECHATRON_POLICY_LIB:-$script_dir/policy.bash}"
fi
if ! declare -F initialize_status_store >/dev/null; then
	# shellcheck disable=SC1090
	source "${MECHATRON_STATUS_STORE_LIB:-$script_dir/status_store.bash}"
fi
if ! declare -F ci_admission_state >/dev/null; then
	# shellcheck disable=SC1090
	source "${MECHATRON_CONTROL_LIB:-$script_dir/control_lib.bash}"
fi
if ! declare -F job_budget_remaining >/dev/null; then
	# shellcheck disable=SC1090
	source "${MECHATRON_RUNTIME_BUDGET_LIB:-$script_dir/runtime_budget.bash}"
fi
if ! declare -F claim_fifo_job >/dev/null; then
	# shellcheck disable=SC1090
	source "${MECHATRON_QUEUE_CLAIM_LIB:-$script_dir/queue_claim.bash}"
fi
if ! declare -F prioritize_queue_batch >/dev/null; then
	# shellcheck disable=SC1090
	source "${MECHATRON_PRIORITY_LIB:-$script_dir/admission_priority.bash}" || exit 1
fi

umask 027
state_dir="${MECHATRON_STATE_DIR:-/var/lib/mechatron-prime}"
github_owner="${MECHATRON_GITHUB_OWNER:-pmarreck}"
legacy_targets_dir="${MECHATRON_LEGACY_TARGETS_DIR:-/etc/mechatron-prime/legacy-targets}"
legacy_targets_store_prefix="${MECHATRON_LEGACY_TARGETS_STORE_PREFIX:-/nix/store}"
badge_dir="${MECHATRON_BADGE_DIR:-/var/lib/mechatron-prime-badges}"
queue_file="$state_dir/queue/builds.ndjson"
queue_lock="$state_dir/queue/.builds.lock"
results_file="$state_dir/results.ndjson"
results_database="$state_dir/results.sqlite3"
current_file="$state_dir/current.json"
active_queue_file="$state_dir/active-queue.ndjson"
worker_id="${MECHATRON_WORKER_ID:-legacy}"
claim_dir="$state_dir"
case "$worker_id" in
	legacy) ;;
	1|2)
		claim_dir="$state_dir/workers/$worker_id"
		current_file="$state_dir/current-$worker_id.json"
		active_queue_file="$state_dir/active-queue-$worker_id.ndjson"
		;;
	*) printf 'Invalid fixed worker identity\n' >&2; exit 2 ;;
esac
repository_lease=9
worker_lease=8
build_timeout="${MECHATRON_BUILD_TIMEOUT_SECONDS:-1800}"
runtime_approvals="${MECHATRON_RUNTIME_APPROVALS_FILE:-/etc/mechatron-prime/runtime-approvals.json}"
prefetch_timeout="${MECHATRON_PREFETCH_TIMEOUT_SECONDS:-60}"
# The lane's own cgroup v2 directory, for stall snapshots around a failed
# source fetch. MECHATRON_CGROUP_DIR overrides it for tests.
lane_cgroup="${MECHATRON_CGROUP_DIR-}"
if [ -z "$lane_cgroup" ] && IFS= read -r cgroup_line < /proc/self/cgroup 2>/dev/null && [[ $cgroup_line == 0::/* ]]; then
	lane_cgroup="/sys/fs/cgroup${cgroup_line#0::}"
fi
# Nix's fetcher cache (a ref-less Git repository) for between-job repacks.
# Unset disables maintenance, so a test run can never touch a real cache. The
# default limit is Git's own gc.autoPackLimit.
tarball_cache_dir="${MECHATRON_TARBALL_CACHE_DIR-}"
tarball_cache_pack_limit="${MECHATRON_TARBALL_CACHE_PACK_LIMIT:-50}"
tarball_cache_repack_timeout="${MECHATRON_TARBALL_CACHE_REPACK_TIMEOUT_SECONDS:-600}"
tarball_cache_lock="$state_dir/.tarball-cache.lock"
cache_push="${MECHATRON_CACHE_PUSH:-true}"
substituters="${MECHATRON_SUBSTITUTERS:-}"
nix_options=()
if [ -n "$substituters" ]; then
	nix_options=(--option substituters "$substituters")
fi

# Private pmarreck repositories need an authenticated GitHub fetch.  The
# systemd EnvironmentFile supplies this read-only credential to the worker;
# Nix receives it only through its configuration channel, never as a command
# argument.  Remove the original variable before launching Nix so it cannot
# leak through a child process environment or an accidental diagnostic dump.
if [ -n "${MECHATRON_GITHUB_READ_TOKEN:-}" ]; then
	github_access_token="access-tokens = github.com=$MECHATRON_GITHUB_READ_TOKEN"
	if [ -n "${NIX_CONFIG:-}" ]; then
		export NIX_CONFIG="${NIX_CONFIG}"$'\n'"$github_access_token"
	else
		export NIX_CONFIG="$github_access_token"
	fi
	unset github_access_token
fi
unset MECHATRON_GITHUB_READ_TOKEN

case "$build_timeout" in
	""|*[!0-9]*|0) printf 'Invalid build timeout\n' >&2; exit 1 ;;
esac
case "$prefetch_timeout" in
	""|*[!0-9]*|0) printf 'Invalid prefetch timeout\n' >&2; exit 1 ;;
esac
case "$cache_push" in
	true|false) ;;
	*) printf 'Invalid cache-push setting\n' >&2; exit 1 ;;
esac
if [ "${1:-}" = --admission-open ]; then
	ci_admission_open "$state_dir"
	exit "$?"
fi

mkdir -p "$state_dir/queue" "$state_dir/batches" "$state_dir/logs" "$state_dir/work" || exit 1
mkdir -p "$claim_dir" || exit 1
# The queue file is watched by a PathChanged unit, and attribute changes count.
# Create and fix mode only when needed so coordinator pre-steps and idle lane
# starts never retrigger the watcher that started them.
prepare_quiet_file() {
	[ -e "$1" ] || : > "$1" || return 1
	[ "$(stat -c '%a' "$1")" = 640 ] || chmod 0640 "$1" || return 1
}
prepare_quiet_file "$queue_file" || exit 1
prepare_quiet_file "$results_file" || exit 1
initialize_status_store "$results_database" || { printf 'Status database is unavailable\n' >&2; exit 1; }
if [ "${1:-}" = --recover-legacy-only ]; then
	[ "$worker_id" = legacy ] || exit 2
	# Coordinator preparation never clears live lane telemetry or claims.
	recover_orphaned_claim "$state_dir" "$queue_file" "$queue_lock" "$results_database" || exit 1
	rm -f -- "$state_dir/current.json" "$state_dir/active-queue.ndjson"
	exit 0
fi
if [ "$worker_id" != legacy ]; then
	worker_lane_begin worker_lease "$state_dir" "$worker_id" "$queue_file" "$queue_lock" "$results_database" || exit "$?"
fi
# A previous clean worker exit removes this file.  If a process was killed
# without its EXIT trap, a fresh worker owns the authoritative recovery path;
# do not present stale claimed work to read-only clients.
rm -f -- "$active_queue_file"
# Recover at most the in-progress claim even when admission is halted, so a
# SIGKILLed drain still returns to the queue instead of vanishing behind halt.
# Historical batch files without a pointer are leftovers and must not be requeued.
recover_orphaned_claim "$claim_dir" "$queue_file" "$queue_lock" "$results_database" \
	|| { printf 'Claimed-batch recovery failed\n' >&2; exit 1; }
admission_state="$(ci_admission_state "$state_dir")" || { printf 'CI admission state is invalid\n' >&2; exit 1; }
if [ "$admission_state" = halted ]; then
	printf 'Mechatron Prime worker: admission halted; queue preserved\n'
	exit 0
fi
[ -d "$badge_dir" ] || { printf 'Badge directory is missing\n' >&2; exit 1; }
migrate_legacy_results "$results_database" "$results_file" "$badge_dir" || { printf 'Legacy result migration failed\n' >&2; exit 1; }

publish_current() {
	local state="$1"
	local repo="${2:-}"
	local sha="${3:-}"
	local target="${4:-}"
	local started_at="${5:-}"
	local pending="${6:-0}"
	local temporary
	temporary="$(mktemp "$state_dir/.current.json.XXXXXX")" || return 1
	if ! jq -cn \
		--arg state "$state" \
		--arg repo "$repo" \
		--arg sha "$sha" \
		--arg target "$target" \
		--arg started_at "$started_at" \
		--argjson pending "$pending" \
		'{state:$state,repo:$repo,sha:$sha,target:$target,started_at:$started_at,pending:$pending}' \
		> "$temporary"
	then
		rm -f "$temporary"
		return 1
	fi
	chmod 0640 "$temporary" || { rm -f "$temporary"; return 1; }
	mv -f "$temporary" "$current_file"
}

# The worker atomically moves the physical queue into a batch before beginning
# a build.  Keep a read-only telemetry copy and remove exactly one queued line
# as it becomes the current job, so clients can distinguish current, claimed,
# and still-waiting work without access to private worker files.
advance_active_queue() {
	local temporary line consumed=false
	temporary="$(mktemp "$state_dir/.active-queue.ndjson.XXXXXX")" || return 1
	while IFS= read -r line || [ -n "$line" ]; do
		if [ "$consumed" = false ] && [ -n "$line" ]; then
			consumed=true
			continue
		fi
		printf '%s\n' "$line"
	done < "$active_queue_file" > "$temporary" || { rm -f -- "$temporary"; return 1; }
	chmod 0640 "$temporary" || { rm -f -- "$temporary"; return 1; }
	mv -f -- "$temporary" "$active_queue_file"
}

publish_current idle || exit 1
batch=""
recovery_line=1
recover_on_interrupt=false
prefetch_pid=""

# Keep the newest green closure of each repository, branch and target across
# Nix garbage collection, which otherwise deletes every unrooted CI output and,
# because keep-outputs is on, the build-time closure a root protects. A
# `nix build --out-link` over outputs that already exist only registers indirect
# roots through the daemon. Extra-output links beyond this build's count are
# removed so an earlier build cannot keep pinning its old closure.
keep_target_root() {
	local outputs_file="$1" repo_name="$2" ref="$3" target="$4" dir stale index
	local -a outputs=()
	mapfile -t outputs < <(grep -v '^$' "$outputs_file")
	[ "${#outputs[@]}" -gt 0 ] || return 1
	dir="$state_dir/gcroots/$repo_name/${ref##*/}/$target"
	mkdir -p "$dir" || return 1
	timeout --kill-after=5s 60s nix build --out-link "$dir/out" "${outputs[@]}" \
		> /dev/null 2>&1 {repository_lease}>&- {worker_lease}>&- || return 1
	while IFS= read -r stale; do
		index="${stale##*/out-}"
		[[ $index =~ ^[0-9]+$ ]] && [ "$index" -ge "${#outputs[@]}" ] && rm -f -- "$stale"
	done < <(find "$dir" -maxdepth 1 -type l -name 'out-*')
	return 0
}

# shellcheck disable=SC2329 # invoked by EXIT trap
cleanup_current() {
	publish_current idle >/dev/null 2>&1 || true
	rm -f -- "$active_queue_file"
}

# shellcheck disable=SC2329 # invoked by INT/TERM traps
interrupt_worker() {
	trap - INT TERM
	if [ -n "$prefetch_pid" ]; then
		kill -TERM "$prefetch_pid" 2>/dev/null || true
		wait "$prefetch_pid" 2>/dev/null || true
		prefetch_pid=""
	fi
	if [ "$recover_on_interrupt" = true ] && [ -n "$batch" ]; then
		# The signal may arrive during the claim's locked rename window. Release
		# our claim descriptor before the recovery helper takes the same lock.
		exec 9>&- || true
		recover_claimed_batch "$batch" "$recovery_line" "$queue_file" "$queue_lock" >/dev/null 2>&1 || true
	fi
	clear_claim_pointer "$claim_dir" >/dev/null 2>&1 || true
	cleanup_current
	exit 143
}

trap cleanup_current EXIT
trap interrupt_worker INT TERM

batch_sequence=0
while :; do
	# A path notification may arrive while this oneshot worker is busy. Claim
	# every batch that accumulated during the prior drain before returning to
	# systemd, so that a coalesced inotify event cannot strand accepted work.
	batch=""
	recovery_line=1
	recover_on_interrupt=false
	# Repack before claiming, so the time is queue wait rather than job time.
	# Another lane mid-job holds the shared cache lease, and maintenance skips.
	if [ -n "$tarball_cache_dir" ]; then
		cache_outcome="$(maintain_tarball_cache "$tarball_cache_dir" "$tarball_cache_lock" \
			"$tarball_cache_pack_limit" "$tarball_cache_repack_timeout" {repository_lease}>&- {worker_lease}>&-)"
		case "$cache_outcome" in *repack*) printf "Mechatron Prime worker: %s\n" "$cache_outcome" ;; esac
	fi
	batch_sequence=$((batch_sequence + 1))
	batch_id="$(date -u +%Y%m%dT%H%M%SZ)-$$-$batch_sequence"
	batch="$state_dir/batches/builds-$batch_id.ndjson"
	if [ "$worker_id" != legacy ]; then
		if claim_fifo_job repository_lease "$state_dir" "$queue_file" "$queue_lock" "$batch" "$claim_dir"; then
			recover_on_interrupt=true
			cp -- "$batch" "$active_queue_file" || exit 1
			chmod 0640 "$batch" "$active_queue_file" || exit 1
		else
			claim_status=$?
			[ "$claim_status" -eq 3 ] && exit 0
			[ "$claim_status" -eq 4 ] && { printf 'Mechatron Prime worker: drain active; queue preserved\n'; exit 0; }
			exit "$claim_status"
		fi
	else
	exec 9> "$queue_lock" || exit 1
	flock 9 || exit 1
	if [ ! -s "$queue_file" ]; then
		exec 9>&-
		printf 'Mechatron Prime worker: queue empty\n'
		exit 0
	fi
	recover_on_interrupt=true
	mv "$queue_file" "$batch" || exit 1
	# A queue slot belongs to (repository, branch), not to a commit. Collapse
	# the claimed batch so the newest commit of each group takes that group's
	# earliest position; displaced commits stay in the batch marked superseded
	# so they still receive a terminal result. Collapsing here, under the claim
	# lock and before any line numbers are handed to interrupt recovery, keeps
	# the batch length stable.
	# Coalescing is an optimisation, never a gate. A batch holding even one
	# malformed record cannot be parsed as a whole, so fall back to draining it
	# uncollapsed: every record still receives its own validation verdict, and
	# a bad record must not be able to stall the queue for everyone else.
	if collapse_queue_batch < "$batch" > "$batch.collapsed" 2>/dev/null; then
		mv -f -- "$batch.collapsed" "$batch" || exit 1
	else
		rm -f -- "$batch.collapsed"
	fi
	: > "$queue_file" || exit 1
	cp -- "$batch" "$active_queue_file" || exit 1
	chmod 0640 "$batch" "$queue_file" "$active_queue_file" || exit 1
	write_claim_pointer "$claim_dir" "$batch" 1 || exit 1
	exec 9>&-
	fi

# Fetches read and extend the fetcher cache for the whole claimed batch, and
# their Nix children inherit this lease. Waiting here means a repack is
# running, which counts as queue time.
exec {cache_lease}> "$tarball_cache_lock" || exit 1
flock -s "$cache_lease" || exit 1

batch_total=0
while IFS= read -r queued_item; do
	[ -n "$queued_item" ] && batch_total=$((batch_total + 1))
done < "$batch"

item_number=0
# write_claim_pointer records $batch as a path in claim.json; it does not write the batch.
# shellcheck disable=SC2094
while IFS= read -r item; do
	[ -n "$item" ] || continue
	item_number=$((item_number + 1))
	advance_active_queue || exit 1
	run_id="$batch_id-$item_number"
	target_results_file="$state_dir/work/$run_id.target-results.ndjson"
	: > "$target_results_file" || exit 1
	chmod 0640 "$target_results_file" || exit 1
	publish_current idle || exit 1
	started_at="$(now_utc)"
	job_started_seconds=$(job_budget_now) || exit 1
	repo=""
	ref=""
	sha=""
	delivery=""
	default_branch=""
	repo_name=""
	status="failure"
	failure_stage="input-validation"
	failure_detail="queue record is not valid JSON with string fields"
	log_file=""
	target_list=""
	paths_file=""
	unconfigured=false

	if jq -e 'type == "object" and (.repo|type == "string") and (.ref|type == "string") and (.sha|type == "string") and (.delivery|type == "string")' <<< "$item" >/dev/null 2>&1; then
		repo="$(jq -r .repo <<< "$item")"
		ref="$(jq -r .ref <<< "$item")"
		sha="$(jq -r .sha <<< "$item")"
		delivery="$(jq -r .delivery <<< "$item")"
		default_branch="$(jq -r '.default_branch // ""' <<< "$item")"
		pending=$((batch_total - item_number))
		publish_current preparing "$repo" "$sha" "" "$started_at" "$pending" || exit 1
		if ! repo_is_owned_by "$repo" "$github_owner"; then
			failure_stage="repo-policy"
			failure_detail="repository is not owned by the configured GitHub owner"
		elif ! valid_ci_branch_ref "$ref"; then
			failure_detail="ref is not an approved CI branch"
		elif ! valid_commit_sha "$sha"; then
			failure_detail="sha is not a 40-hex Git commit"
		elif ! valid_delivery_id "$delivery"; then
			failure_detail="delivery ID is invalid"
		else
			repo_name="$(repo_name_from_full_name "$repo")"
			run_id="$run_id-${sha:0:12}"
			if [ "$(jq -r '.superseded // false' <<< "$item")" = true ]; then
				# Displaced in the queue by a newer commit on the same branch.
				# It never ran, so it is stopped rather than failed, and it
				# publishes only its own commit badge: the repository's current
				# status belongs to the commit that actually built.
				status="stopped"
				failure_stage="superseded"
				failure_detail="superseded by a newer commit on $ref"
			else
			runtime_policy_error=false
			if ! runtime_limit=$(job_runtime_limit "$build_timeout" "$repo" "$runtime_approvals"); then
				runtime_policy_error=true
				runtime_limit=0
			fi
			job_deadline=$((job_started_seconds+runtime_limit))
			log_file="$state_dir/logs/$repo_name-$run_id.log"
			target_list="$state_dir/work/$repo_name-$run_id.targets"
			paths_file="$state_dir/work/$repo_name-$run_id.paths"
			: > "$log_file"
			: > "$target_list"
			: > "$paths_file"
			chmod 0640 "$log_file" "$target_list" "$paths_file"
			{
				printf 'started_at=%s\n' "$started_at"
				printf 'delivery=%s\nrepo=%s\nref=%s\ndefault_branch=%s\nsha=%s\n' "$delivery" "$repo" "$ref" "$default_branch" "$sha"
			} >> "$log_file"

			flake="github:$repo/$sha"
			prefetch_out="$state_dir/work/$repo_name-$run_id.prefetch.json"
			prefetch_err="$state_dir/work/$repo_name-$run_id.prefetch.err"
			: > "$prefetch_out"
			: > "$prefetch_err"
			chmod 0640 "$prefetch_out" "$prefetch_err"
			prefetch_attempts="${MECHATRON_GITHUB_RETRY_ATTEMPTS:-4}"
			attempt=1
			prefetch_status=1
			prefetch_err_text=""
			fetch_runs=0
			hang_retried=false
			# Background so INT/TERM can run while prefetch is in flight. A
			# foreground wait on a hung child would delay the trap until the
			# child exited, which is how a claimed job vanished on SIGKILL.
			# Fast GitHub 502/timeout blips retry with injected backoff. A fetch
			# stopped by its own hang bound (124) or kill (137+) gets one immediate
			# retry: those hangs have cleared within minutes, and worker signals
			# never reach this loop because interrupt_worker exits first.
			while [ "$attempt" -le "$prefetch_attempts" ]; do
				fetch_runs=$((fetch_runs + 1))
				{
					printf '\n=== nix flake prefetch %s attempt %s ===\n' "$flake" "$fetch_runs"
					date -u +%Y-%m-%dT%H:%M:%SZ
				} >> "$log_file"
				: > "$prefetch_out"
				: > "$prefetch_err"
				if ! prefetch_budget=$(job_budget_slice "$job_deadline" "$prefetch_timeout"); then prefetch_status=124; break; fi
				stall_before="$(cgroup_stall_snapshot "$lane_cgroup")"
				timeout --kill-after=5s "$prefetch_budget" nix flake prefetch --json "$flake" \
					> "$prefetch_out" 2> "$prefetch_err" {repository_lease}>&- {worker_lease}>&- &
				prefetch_pid=$!
				wait "$prefetch_pid"
				prefetch_status=$?
				prefetch_pid=""
				cat "$prefetch_err" >> "$log_file"
				if [ "$prefetch_status" -ne 0 ]; then
					printf "prefetch stall before %s\nprefetch stall after %s\n" "$stall_before" "$(cgroup_stall_snapshot "$lane_cgroup")" >> "$log_file"
				fi
				prefetch_err_text="$(cat "$prefetch_err" 2>/dev/null || true)"
				if [ "$prefetch_status" -eq 0 ]; then
					break
				fi
				if build_exit_was_stopped "$prefetch_status"; then
					[ "$hang_retried" = false ] || break
					hang_retried=true
					continue
				fi
				if ! github_failure_is_retryable "$prefetch_status" "$prefetch_err_text"; then
					break
				fi
				if [ "$attempt" -eq "$prefetch_attempts" ]; then
					break
				fi
				backoff=$(github_retry_backoff_seconds "$attempt")
				if ! backoff_budget=$(job_budget_slice "$job_deadline" "$backoff"); then prefetch_status=124; break; fi
				mechatron_sleep "$backoff_budget"
				attempt=$((attempt + 1))
			done
			prefetch_json="$(cat "$prefetch_out" 2>/dev/null || true)"
			if [ "$prefetch_status" -ne 0 ]; then
				if [ "$runtime_policy_error" = true ]; then
					failure_stage="runtime-policy"
					failure_detail="runtime approval registry is invalid; job not started"
				elif ! job_budget_remaining "$job_deadline" "$(job_budget_now)" >/dev/null; then
					status="stopped"; failure_stage="execution-timeout"; failure_detail="whole-job runtime budget exhausted"
				elif [ "$prefetch_status" -eq 124 ] || github_failure_is_retryable "$prefetch_status" "$prefetch_err_text"; then
					status="stopped"
					failure_stage="github-timeout"
					failure_detail="GitHub source fetch timed out after $fetch_runs attempts"
				elif build_exit_was_stopped "$prefetch_status"; then
					status="stopped"
					failure_stage="source-fetch"
					failure_detail="could not fetch the exact queued flake source"
				else
					failure_stage="source-fetch"
					failure_detail="could not fetch the exact queued flake source"
				fi
			elif ! source_store="$(jq -er '.storePath | strings | select(startswith("/"))' <<< "$prefetch_json" 2>> "$log_file")" || [ ! -d "$source_store" ]; then
				failure_stage="source-fetch"
				failure_detail="Nix returned no usable source store path"
			else
				manifest_targets_file="$source_store/.mechatron-prime/targets"
				legacy_targets_file="$legacy_targets_dir/$repo_name.targets"
				targets_file=""
				target_source=""
				invalid_target=""
				if [ -L "$manifest_targets_file" ] || { [ -e "$manifest_targets_file" ] && [ ! -f "$manifest_targets_file" ]; }; then
					failure_stage="target-manifest"
					failure_detail=".mechatron-prime/targets is not a regular file"
				elif [ -f "$manifest_targets_file" ]; then
					targets_file="$manifest_targets_file"
					target_source="exact-commit manifest"
				elif [ -f "$legacy_targets_file" ] && [ ! -L "$legacy_targets_file" ]; then
					targets_file="$legacy_targets_file"
					target_source="root-owned legacy fallback"
				elif [ -L "$legacy_targets_file" ]; then
					resolved_legacy_targets_file="$(readlink -f -- "$legacy_targets_file" 2>/dev/null || true)"
					case "$resolved_legacy_targets_file" in
						"$legacy_targets_store_prefix"/*)
							if [ -f "$resolved_legacy_targets_file" ]; then
								targets_file="$resolved_legacy_targets_file"
								target_source="root-owned immutable-store legacy fallback"
							fi
							;;
					esac
					if [ -z "$targets_file" ]; then
						failure_stage="target-manifest"
						failure_detail="legacy target symlink does not resolve into the immutable store"
					fi
				else
					failure_stage="target-manifest"
					failure_detail=".mechatron-prime/targets is missing and no legacy target file exists"
					unconfigured=true
				fi
				if [ -n "$targets_file" ]; then
					printf 'targets_source=%s\n' "$target_source" >> "$log_file"
					while IFS= read -r target || [ -n "$target" ]; do
						[[ "$target" =~ ^[[:space:]]*$ ]] && continue
						[[ "$target" =~ ^[[:space:]]*# ]] && continue
						if ! valid_nix_target "$target"; then
							invalid_target="$target"
							break
						fi
						printf '%s\n' "$target" >> "$target_list"
					done < "$targets_file"
				fi

				if [ "$failure_stage" = "target-manifest" ]; then
					:
				elif [ -n "$invalid_target" ]; then
					failure_stage="target-validation"
					failure_detail="target manifest contains an invalid target"
				elif [ ! -s "$target_list" ]; then
					failure_stage="target-manifest"
					failure_detail="target manifest has no active targets"
					unconfigured=true
				elif ! write_badge_status "$badge_dir" "$repo" BUILDING "$sha"; then
					failure_stage="status-publication"
					failure_detail="could not publish BUILDING badge"
				else
					status="success"
					failure_stage=""
					failure_detail=""
					target_number=0
					while IFS= read -r target; do
						target_number=$((target_number + 1))
						pending=$((batch_total - item_number))
						publish_current building "$repo" "$sha" "$target" "$started_at" "$pending" || exit 1
						target_paths="$state_dir/work/$repo_name-$run_id-$target.paths"
						{
							printf '\n=== nix build %s#%s ===\n' "$flake" "$target"
							date -u +%Y-%m-%dT%H:%M:%SZ
						} >> "$log_file"
						MECHATRON_CURRENT_REPO_NAME="$repo_name" job_budget_command "$job_deadline" "$runtime_limit" \
							nix build "${nix_options[@]}" --no-link --print-out-paths "$flake#$target" \
							> "$target_paths" 2>> "$log_file" {repository_lease}>&- {worker_lease}>&-
						build_status=$?
						target_status=success
						if [ "$build_status" -ne 0 ]; then
							if build_exit_was_stopped "$build_status"; then
								target_status=stopped
							else
								target_status=failure
							fi
						fi
						output_paths_json="$(jq -Rsc 'split("\n") | map(select(length > 0))' < "$target_paths")" || exit 1
						jq -cn \
							--argjson ordinal "$target_number" \
							--arg target "$target" \
							--arg status "$target_status" \
							--argjson output_paths "$output_paths_json" \
							'{ordinal:$ordinal,target:$target,status:$status,output_paths:$output_paths}' \
							>> "$target_results_file" || exit 1
						if [ "$build_status" -ne 0 ]; then
							if [ "$target_status" = stopped ]; then
								status="stopped"
								failure_stage="build-stopped"
								failure_detail="target stopped: $target"
							else
								status="failure"
								failure_stage="nix-build"
								failure_detail="target failed: $target"
							fi
							break
						fi
						cat "$target_paths" >> "$paths_file"
						keep_target_root "$target_paths" "$repo_name" "$ref" "$target" \
							|| printf "warning: could not keep a GC root for %s\n" "$target" >> "$log_file"
					done < "$target_list"
					# A failed or stopped target ends the build, so the manifest
					# targets after it never ran. Record them as skipped rather
					# than leave the run looking as if it had fewer targets.
					skipped_number=0
					while IFS= read -r target; do
						skipped_number=$((skipped_number + 1))
						[ "$skipped_number" -le "$target_number" ] && continue
						jq -cn \
							--argjson ordinal "$skipped_number" \
							--arg target "$target" \
							'{ordinal:$ordinal,target:$target,status:"skipped",output_paths:[]}' \
							>> "$target_results_file" || exit 1
					done < "$target_list"
				fi
			fi
			fi
		fi
	fi

	if [ "$status" = "success" ]; then
		if [ ! -s "$paths_file" ]; then
			status="failure"
			failure_stage="nix-build"
			failure_detail="build produced no output paths"
		else
			sort -u "$paths_file" > "$paths_file.sorted"
			if [ "$cache_push" = true ]; then
				MECHATRON_CURRENT_REPO_NAME="$repo_name" job_budget_command "$job_deadline" "$runtime_limit" attic push --stdin local:fleet \
					< "$paths_file.sorted" >> "$log_file" 2>&1 {repository_lease}>&- {worker_lease}>&-
				attic_status=$?
				if [ "$attic_status" -ne 0 ]; then
					status="failure"
					failure_stage="attic-push"
					failure_detail="failed to push build outputs to local:fleet"
				fi
			fi
		fi
	fi

	if [ -n "$log_file" ] && [ "$runtime_policy_error" = false ] && ! job_budget_remaining "$job_deadline" "$(job_budget_now)" >/dev/null; then
		status="stopped"; failure_stage="execution-timeout"; failure_detail="whole-job runtime budget exhausted; request an approved exception before retrying"
	fi
	if [ -n "$repo_name" ]; then
		if [ "$failure_stage" = "superseded" ]; then
			# Commit-addressable only. A commit displaced from the queue never
			# ran, so it must not overwrite the repository's latest badge — that
			# belongs to the commit that actually built.
			write_commit_badge_status "$badge_dir" "$repo" SUPERSEDED "$sha" || true
		elif [ "$status" = "success" ]; then
			if ! write_badge_status "$badge_dir" "$repo" PASSING "$sha"; then
				status="failure"
				failure_stage="status-publication"
				failure_detail="could not publish PASSING badge"
			fi
		elif [ "$unconfigured" = true ]; then
			# Not onboarded: there is nothing to verify, so the badge claims
			# neither a pass nor a failure. The ledger still records a failure.
			write_badge_status "$badge_dir" "$repo" UNCONFIGURED "$sha" || true
		elif [ "$status" = "stopped" ]; then
			# A stopped build makes no claim about the repository, so it must
			# not publish the failing badge that sends its agent debugging.
			write_badge_status "$badge_dir" "$repo" STOPPED "$sha" || true
		else
			write_badge_status "$badge_dir" "$repo" FAILING "$sha" || true
		fi
	fi

	finished_at="$(now_utc)"
	if [ -n "$log_file" ] && [ -f "$log_file" ]; then
		{
			printf '\n=== result ===\n'
			if [ -n "$failure_stage" ]; then
				printf 'status=%s failure_stage=%s\n' "$status" "$failure_stage"
			else
				printf 'status=%s\n' "$status"
			fi
			jq -r '(if .status == "success" then "PASS" elif .status == "failure" then "FAIL" else (.status | ascii_upcase) end) + "  " + .target' \
				< "$target_results_file"
		} >> "$log_file" || exit 1
	fi
	targets_json='[]'
	paths_json='[]'
	[ -n "$target_list" ] && [ -f "$target_list" ] &&
		targets_json="$(jq -Rsc 'split("\n") | map(select(length > 0))' < "$target_list")"
	[ -n "$paths_file" ] && [ -f "$paths_file" ] &&
		paths_json="$(jq -Rsc 'split("\n") | map(select(length > 0))' < "$paths_file")"
	result_json="$(jq -cn \
		--arg started_at "$started_at" \
		--arg finished_at "$finished_at" \
		--arg delivery "$delivery" \
		--arg repo "$repo" \
		--arg ref "$ref" \
		--arg sha "$sha" \
		--arg status "$status" \
		--arg failure_stage "$failure_stage" \
		--arg failure_detail "$failure_detail" \
		--arg log "$log_file" \
		--argjson targets "$targets_json" \
		--argjson paths "$paths_json" \
		'{started_at:$started_at,finished_at:$finished_at,delivery:$delivery,repo:$repo,ref:$ref,sha:$sha,status:$status,failure_stage:$failure_stage,failure_detail:$failure_detail,targets:$targets,paths:$paths,log:$log}')" || exit 1
	record_ci_result "$results_database" "$run_id" "$delivery" "$repo" "$ref" "$sha" \
		"$default_branch" "$started_at" "$finished_at" "$status" "$failure_stage" \
		"$failure_detail" "$log_file" "$target_results_file" || exit 1
	(flock 7 && printf '%s\n' "$result_json" >> "$results_file") 7> "$state_dir/.results.lock" || exit 1
	chmod 0640 "$results_file" || exit 1
	recovery_line=$((item_number + 1))
	# claim.json is the write target; $batch is only recorded as a path.
	# shellcheck disable=SC2094
	write_claim_pointer "$claim_dir" "$batch" "$recovery_line" || exit 1
	printf 'Mechatron Prime worker: %s@%s => %s (%s)\n' "$repo" "$sha" "$status" "$failure_stage"
done < "$batch"

clear_claim_pointer "$claim_dir" || exit 1
exec {repository_lease}>&-
exec {cache_lease}>&-
repository_lease=9
recover_on_interrupt=false
done

# Repository and queue-item failures are CI results, not worker-health failures.
# Every handled result is recorded above; only an earlier control-plane error
# (queue/state/badge bookkeeping) may leave this oneshot unit nonzero.
exit 0
