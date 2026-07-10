#!/usr/bin/env bash
# Sequentially drain the one global queue through explicit repository policies.
set -u
set +e

if ! declare -F repo_is_allowed >/dev/null; then
	script_dir="$(cd "$(dirname "$0")" && pwd)"
	# Deployment may override the packaged library path.
	# shellcheck disable=SC1090
	source "${MECHATRON_POLICY_LIB:-$script_dir/policy.bash}"
fi

umask 027
state_dir="${MECHATRON_STATE_DIR:-/var/lib/mechatron-prime}"
allowlist="${MECHATRON_REPOS_ALLOWLIST:-/etc/mechatron-prime/repos.allowlist}"
targets_dir="${MECHATRON_TARGETS_DIR:-/etc/mechatron-prime/targets}"
badge_dir="${MECHATRON_BADGE_DIR:-/var/lib/mechatron-prime-badges}"
queue_file="$state_dir/queue/builds.ndjson"
queue_lock="$state_dir/queue/.builds.lock"
results_file="$state_dir/results.ndjson"
build_timeout="${MECHATRON_BUILD_TIMEOUT_SECONDS:-7200}"
cache_push="${MECHATRON_CACHE_PUSH:-true}"
substituters="${MECHATRON_SUBSTITUTERS:-}"

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

overall_failures=0
item_number=0
while IFS= read -r item; do
	[ -n "$item" ] || continue
	item_number=$((item_number + 1))
	started_at="$(now_utc)"
	repo=""
	ref=""
	sha=""
	delivery=""
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
		if ! repo_is_allowed "$repo" "$allowlist"; then
			failure_stage="repo-policy"
			failure_detail="repository is not allowlisted"
		elif ! valid_yolo_ref "$ref"; then
			failure_detail="ref is not refs/heads/yolo"
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
				printf 'delivery=%s\nrepo=%s\nref=%s\nsha=%s\n' "$delivery" "$repo" "$ref" "$sha"
			} >> "$log_file"

			targets_file="$targets_dir/$repo_name.targets"
			if [ ! -s "$targets_file" ]; then
				failure_stage="configuration"
				failure_detail="target file is empty or missing"
			else
				invalid_target=""
				while IFS= read -r target; do
					[[ "$target" =~ ^[[:space:]]*$ ]] && continue
					[[ "$target" =~ ^[[:space:]]*# ]] && continue
					if ! valid_nix_target "$target"; then
						invalid_target="$target"
						break
					fi
					printf '%s\n' "$target" >> "$target_list"
				done < "$targets_file"

				if [ -n "$invalid_target" ]; then
					failure_stage="target-validation"
					failure_detail="target file contains an invalid target"
				elif [ ! -s "$target_list" ]; then
					failure_stage="configuration"
					failure_detail="target file has no active targets"
				elif ! write_badge_status "$badge_dir" "$repo" BUILDING; then
					failure_stage="status-publication"
					failure_detail="could not publish BUILDING badge"
				else
					status="success"
					failure_stage=""
					failure_detail=""
					flake="github:$repo/$sha"
					while IFS= read -r target; do
						target_paths="$state_dir/work/$repo_name-$run_id-$target.paths"
						nix_options=()
						if [ -n "$substituters" ]; then
							nix_options=(--option substituters "$substituters")
						fi
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
