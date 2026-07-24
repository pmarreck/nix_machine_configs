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
build_timeout="${MECHATRON_BUILD_TIMEOUT_SECONDS:-7200}"
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
case "$cache_push" in
	true|false) ;;
	*) printf 'Invalid cache-push setting\n' >&2; exit 1 ;;
esac

mkdir -p "$state_dir/queue" "$state_dir/batches" "$state_dir/logs" "$state_dir/work" || exit 1
touch "$queue_file" "$results_file" || exit 1
chmod 0640 "$queue_file" "$results_file" || exit 1
# A previous clean worker exit removes this file.  If a process was killed
# without its EXIT trap, a fresh worker owns the authoritative recovery path;
# do not present stale claimed work to read-only clients.
rm -f -- "$active_queue_file"
admission_state="$(ci_admission_state "$state_dir")" || { printf 'CI admission state is invalid\n' >&2; exit 1; }
if [ "$admission_state" = halted ]; then
	printf 'Mechatron Prime worker: admission halted; queue preserved\n'
	exit 0
fi
[ -d "$badge_dir" ] || { printf 'Badge directory is missing\n' >&2; exit 1; }
initialize_status_store "$results_database" || { printf 'Status database is unavailable\n' >&2; exit 1; }
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

# shellcheck disable=SC2329 # invoked by EXIT trap
cleanup_current() {
	publish_current idle >/dev/null 2>&1 || true
	rm -f -- "$active_queue_file"
}

# shellcheck disable=SC2329 # invoked by INT/TERM traps
interrupt_worker() {
	trap - INT TERM
	if [ "$recover_on_interrupt" = true ] && [ -n "$batch" ]; then
		# The signal may arrive during the claim's locked rename window. Release
		# our claim descriptor before the recovery helper takes the same lock.
		exec 9>&- || true
		recover_claimed_batch "$batch" "$recovery_line" "$queue_file" "$queue_lock" >/dev/null 2>&1 || true
	fi
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
	batch_sequence=$((batch_sequence + 1))
	batch_id="$(date -u +%Y%m%dT%H%M%SZ)-$$-$batch_sequence"
	batch="$state_dir/batches/builds-$batch_id.ndjson"
	exec 9> "$queue_lock" || exit 1
	flock 9 || exit 1
	if [ ! -s "$queue_file" ]; then
		exec 9>&-
		printf 'Mechatron Prime worker: queue empty\n'
		exit 0
	fi
	recover_on_interrupt=true
	mv "$queue_file" "$batch" || exit 1
	: > "$queue_file" || exit 1
	cp -- "$batch" "$active_queue_file" || exit 1
	chmod 0640 "$batch" "$queue_file" "$active_queue_file" || exit 1
	exec 9>&-

batch_total=0
while IFS= read -r queued_item; do
	[ -n "$queued_item" ] && batch_total=$((batch_total + 1))
done < "$batch"

item_number=0
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
			{
				printf '\n=== nix flake prefetch %s ===\n' "$flake"
				date -u +%Y-%m-%dT%H:%M:%SZ
			} >> "$log_file"
			prefetch_json="$(nix flake prefetch --json "$flake" 2>> "$log_file")"
			prefetch_status=$?
			if [ "$prefetch_status" -ne 0 ]; then
				failure_stage="source-fetch"
				failure_detail="could not fetch the exact queued flake source"
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
						MECHATRON_CURRENT_REPO_NAME="$repo_name" timeout "$build_timeout" \
							nix build "${nix_options[@]}" --no-link --print-out-paths "$flake#$target" \
							> "$target_paths" 2>> "$log_file"
						build_status=$?
						target_status=success
						[ "$build_status" -eq 0 ] || target_status=failure
						output_paths_json="$(jq -Rsc 'split("\n") | map(select(length > 0))' < "$target_paths")" || exit 1
						jq -cn \
							--argjson ordinal "$target_number" \
							--arg target "$target" \
							--arg status "$target_status" \
							--argjson output_paths "$output_paths_json" \
							'{ordinal:$ordinal,target:$target,status:$status,output_paths:$output_paths}' \
							>> "$target_results_file" || exit 1
						if [ "$build_status" -ne 0 ]; then
							status="failure"
							failure_stage="nix-build"
							failure_detail="target failed: $target"
							break
						fi
						cat "$target_paths" >> "$paths_file"
					done < "$target_list"
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
				MECHATRON_CURRENT_REPO_NAME="$repo_name" attic push --stdin local:fleet \
					< "$paths_file.sorted" >> "$log_file" 2>&1
				attic_status=$?
				if [ "$attic_status" -ne 0 ]; then
					status="failure"
					failure_stage="attic-push"
					failure_detail="failed to push build outputs to local:fleet"
				fi
			fi
		fi
	fi

	if [ -n "$repo_name" ]; then
		if [ "$status" = "success" ]; then
			if ! write_badge_status "$badge_dir" "$repo" PASSING "$sha"; then
				status="failure"
				failure_stage="status-publication"
				failure_detail="could not publish PASSING badge"
			fi
		else
			write_badge_status "$badge_dir" "$repo" FAILING "$sha" || true
		fi
	fi

	finished_at="$(now_utc)"
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
	printf '%s\n' "$result_json" >> "$results_file" || exit 1
	chmod 0640 "$results_file" || exit 1
	recovery_line=$((item_number + 1))
	printf 'Mechatron Prime worker: %s@%s => %s (%s)\n' "$repo" "$sha" "$status" "$failure_stage"
done < "$batch"

recover_on_interrupt=false
done

# Repository and queue-item failures are CI results, not worker-health failures.
# Every handled result is recorded above; only an earlier control-plane error
# (queue/state/badge bookkeeping) may leave this oneshot unit nonzero.
exit 0
