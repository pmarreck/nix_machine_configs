#!/usr/bin/env bash
# Sequentially drain the one global queue through owner and manifest policies.
set -u
set +e

if ! declare -F repo_is_owned_by >/dev/null; then
	script_dir="$(cd "$(dirname "$0")" && pwd)"
	# Deployment may override the packaged library path.
	# shellcheck disable=SC1090
	source "${MECHATRON_POLICY_LIB:-$script_dir/policy.bash}"
fi

umask 027
state_dir="${MECHATRON_STATE_DIR:-/var/lib/mechatron-prime}"
github_owner="${MECHATRON_GITHUB_OWNER:-pmarreck}"
legacy_targets_dir="${MECHATRON_LEGACY_TARGETS_DIR:-/etc/mechatron-prime/legacy-targets}"
badge_dir="${MECHATRON_BADGE_DIR:-/var/lib/mechatron-prime-badges}"
queue_file="$state_dir/queue/builds.ndjson"
queue_lock="$state_dir/queue/.builds.lock"
results_file="$state_dir/results.ndjson"
current_file="$state_dir/current.json"
build_timeout="${MECHATRON_BUILD_TIMEOUT_SECONDS:-7200}"
cache_push="${MECHATRON_CACHE_PUSH:-true}"
substituters="${MECHATRON_SUBSTITUTERS:-}"
nix_options=()
if [ -n "$substituters" ]; then
	nix_options=(--option substituters "$substituters")
fi

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
[ -d "$badge_dir" ] || { printf 'Badge directory is missing\n' >&2; exit 1; }

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

publish_current idle || exit 1
trap 'publish_current idle >/dev/null 2>&1 || true' EXIT

batch_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
batch="$state_dir/batches/builds-$batch_id.ndjson"
exec 9> "$queue_lock" || exit 1
flock 9 || exit 1
if [ ! -s "$queue_file" ]; then
	printf 'Mechatron Prime worker: queue empty\n'
	exit 0
fi
mv "$queue_file" "$batch" || exit 1
: > "$queue_file" || exit 1
chmod 0640 "$batch" "$queue_file" || exit 1
exec 9>&-

batch_total=0
while IFS= read -r queued_item; do
	[ -n "$queued_item" ] && batch_total=$((batch_total + 1))
done < "$batch"

overall_failures=0
item_number=0
while IFS= read -r item; do
	[ -n "$item" ] || continue
	item_number=$((item_number + 1))
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

	if jq -e 'type == "object" and (.repo|type == "string") and (.ref|type == "string") and (.sha|type == "string") and (.delivery|type == "string") and (.default_branch|type == "string")' <<< "$item" >/dev/null 2>&1; then
		repo="$(jq -r .repo <<< "$item")"
		ref="$(jq -r .ref <<< "$item")"
		sha="$(jq -r .sha <<< "$item")"
		delivery="$(jq -r .delivery <<< "$item")"
		default_branch="$(jq -r .default_branch <<< "$item")"
		if ! repo_is_owned_by "$repo" "$github_owner"; then
			failure_stage="repo-policy"
			failure_detail="repository is not owned by the configured GitHub owner"
		elif ! repo_ref_is_default_branch "$repo" "$ref" "$default_branch"; then
			failure_detail="ref is not the signed repository default branch"
		elif ! valid_commit_sha "$sha"; then
			failure_detail="sha is not a 40-hex Git commit"
		elif ! valid_delivery_id "$delivery"; then
			failure_detail="delivery ID is invalid"
		else
			repo_name="$(repo_name_from_full_name "$repo")"
			run_id="$batch_id-$item_number-${sha:0:12}"
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
				elif ! write_badge_status "$badge_dir" "$repo" BUILDING; then
					failure_stage="status-publication"
					failure_detail="could not publish BUILDING badge"
				else
					status="success"
					failure_stage=""
					failure_detail=""
					while IFS= read -r target; do
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
			if ! write_badge_status "$badge_dir" "$repo" PASSING; then
				status="failure"
				failure_stage="status-publication"
				failure_detail="could not publish PASSING badge"
			fi
		else
			write_badge_status "$badge_dir" "$repo" FAILING || true
		fi
	fi

	finished_at="$(now_utc)"
	targets_json='[]'
	paths_json='[]'
	[ -n "$target_list" ] && [ -f "$target_list" ] &&
		targets_json="$(jq -Rsc 'split("\n") | map(select(length > 0))' < "$target_list")"
	[ -n "$paths_file" ] && [ -f "$paths_file" ] &&
		paths_json="$(jq -Rsc 'split("\n") | map(select(length > 0))' < "$paths_file")"
	jq -cn \
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
		'{started_at:$started_at,finished_at:$finished_at,delivery:$delivery,repo:$repo,ref:$ref,sha:$sha,status:$status,failure_stage:$failure_stage,failure_detail:$failure_detail,targets:$targets,paths:$paths,log:$log}' \
		>> "$results_file"
	chmod 0640 "$results_file"
	if [ "$status" != "success" ]; then
		overall_failures=$((overall_failures + 1))
	fi
	printf 'Mechatron Prime worker: %s@%s => %s (%s)\n' "$repo" "$sha" "$status" "$failure_stage"
done < "$batch"

[ "$overall_failures" -eq 0 ]
