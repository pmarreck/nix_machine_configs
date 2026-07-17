#!/usr/bin/env bash
# HMAC authentication is enforced by the webhook trigger rendered in receiver.nix.
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
queue_dir="$state_dir/queue"
queue_file="$queue_dir/builds.ndjson"
queue_lock="$queue_dir/.builds.lock"
accepted_file="$state_dir/accepted.ndjson"
events_file="$state_dir/events.ndjson"

install -d -m 0750 "$state_dir" "$state_dir/logs" "$queue_dir" || exit 1
touch "$queue_file" "$accepted_file" "$events_file" || exit 1
chmod 0640 "$queue_file" "$accepted_file" "$events_file" || exit 1

event="${GITHUB_EVENT:-}"
delivery="${GITHUB_DELIVERY:-}"
repo="${GITHUB_REPOSITORY:-}"
ref="${GITHUB_REF:-}"
sha="${GITHUB_SHA:-}"
default_branch="${GITHUB_DEFAULT_BRANCH:-}"
ts="$(now_utc)"
allowed=false
repo_is_owned_by "$repo" "$github_owner" && allowed=true

jq -cn \
	--arg ts "$ts" \
	--arg event "$event" \
	--arg delivery "$delivery" \
	--arg repo "$repo" \
	--arg ref "$ref" \
	--arg sha "$sha" \
	--arg default_branch "$default_branch" \
	--argjson allowed "$allowed" \
	'{ts:$ts,event:$event,delivery:$delivery,repo:$repo,ref:$ref,sha:$sha,default_branch:$default_branch,allowed:$allowed}' \
	>> "$events_file" || exit 1

if [ "$event" = "ping" ]; then
	printf 'Mechatron Prime ping accepted\n'
	exit 0
fi

if [ "$event" != "push" ] || [ "$allowed" != true ] ||
	! valid_delivery_id "$delivery" || ! valid_ci_branch_ref "$ref" || ! valid_commit_sha "$sha"
then
	printf 'Mechatron Prime ignored webhook outside policy\n'
	exit 0
fi

exec 9> "$queue_lock" || exit 1
flock 9 || exit 1

if [ -s "$accepted_file" ]; then
	jq -e -s \
		--arg delivery "$delivery" \
		--arg repo "$repo" \
		--arg sha "$sha" \
		'any(.[]; .delivery == $delivery or (.repo == $repo and .sha == $sha))' \
		"$accepted_file" >/dev/null 2>&1
	dedupe_status=$?
	if [ "$dedupe_status" -eq 0 ]; then
		printf 'Mechatron Prime ignored duplicate delivery or build\n'
		exit 0
	elif [ "$dedupe_status" -gt 1 ]; then
		printf 'Mechatron Prime dedupe ledger is invalid\n' >&2
		exit 1
	fi
fi

record="$(jq -cn \
	--arg ts "$ts" \
	--arg delivery "$delivery" \
	--arg repo "$repo" \
	--arg ref "$ref" \
	--arg sha "$sha" \
	--arg default_branch "$default_branch" \
	'{ts:$ts,delivery:$delivery,repo:$repo,ref:$ref,sha:$sha,default_branch:$default_branch,status:"queued"}')" || exit 1
printf '%s\n' "$record" >> "$queue_file" || exit 1
printf '%s\n' "$record" >> "$accepted_file" || exit 1
chmod 0640 "$queue_file" "$accepted_file" || exit 1

printf 'Mechatron Prime queued %s@%s\n' "$repo" "$sha"
