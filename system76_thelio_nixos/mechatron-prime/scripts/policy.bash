#!/usr/bin/env bash
# Pure validation and badge rendering shared by the webhook receiver and worker.

valid_repo_full_name() {
	local repo="${1:-}"
	local owner
	local name
	[[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}/[A-Za-z0-9._-]{1,100}$ ]] || return 1
	owner="${repo%%/*}"
	name="${repo#*/}"
	[ "$owner" != "." ] && [ "$owner" != ".." ] &&
		[ "$name" != "." ] && [ "$name" != ".." ]
}

# Admit only an exact GitHub owner, never a user-controlled repository list.
# The receiver and worker both repeat this check because queue storage is not a
# security boundary.
repo_is_owned_by() {
	local repo="${1:-}"
	local owner="${2:-}"
	valid_repo_full_name "$repo" || return 1
	[[ "$owner" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]] || return 1
	[ "${repo%%/*}" = "$owner" ]
}

repo_name_from_full_name() {
	local repo="${1:-}"
	valid_repo_full_name "$repo" || return 1
	printf '%s\n' "${repo#*/}"
}

valid_commit_sha() {
	local sha="${1:-}"
	[[ "$sha" =~ ^[0-9A-Fa-f]{40}$ ]]
}

valid_delivery_id() {
	local delivery="${1:-}"
	[[ "$delivery" =~ ^[A-Za-z0-9-]{1,128}$ ]]
}

valid_branch_ref() {
	local ref="${1:-}"
	[[ "$ref" =~ ^refs/heads/ ]] || return 1
	valid_branch_name "${ref#refs/heads/}"
}

# Reject unsafe Git refs while retaining normal GitHub default-branch forms.
valid_branch_name() {
	local branch="${1:-}"
	[[ "$branch" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ ]] || return 1
	[[ "$branch" != *..* ]] || return 1
	[[ "$branch" != *//* ]] || return 1
	[[ "$branch" != */ ]] || return 1
	[[ "$branch" != *. ]] || return 1
	[[ "$branch" != *@\{* ]]
}

# Keep CI predictable while supporting Peter-originated repositories and forks
# that retain the upstream main branch. Feature branches remain out of scope.
valid_ci_branch_ref() {
	local ref="${1:-}"
	valid_branch_ref "$ref" || return 1
	case "${ref#refs/heads/}" in
		yolo|master|main) return 0 ;;
		*) return 1 ;;
	esac
}

valid_nix_target() {
	local target="${1:-}"
	[[ "$target" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]]
}

now_utc() {
	if [ -n "${MECHATRON_NOW:-}" ]; then
		printf '%s\n' "$MECHATRON_NOW"
	else
		date -u +%Y-%m-%dT%H:%M:%SZ
	fi
}

# Collapse a claimed batch so a queue slot belongs to (repository, branch)
# rather than to a commit. Within each group the newest record — the last one
# accepted, since the queue is append-ordered — takes the group's EARLIEST
# position, and the commits it displaces keep the group's remaining positions
# marked `superseded`.
#
# The displaced records are retained rather than deleted because superseding is
# irreversible: the receiver dedupes against an append-only accepted ledger, so
# a dropped commit could never be rebuilt from a webhook and would end up with
# no CI verdict at all. Keeping them in place also keeps the batch line count
# stable, which interrupt recovery indexes into by line number.
#
# Reads NDJSON on stdin, writes NDJSON on stdout. Records missing repo or ref
# group under the empty key and are therefore left for downstream validation to
# reject rather than being silently coalesced together.
collapse_queue_batch() {
	jq -c -s '
		[ to_entries[] | .value + {__i: .key} ]
		| group_by(
			if (.repo | type) == "string" and (.ref | type) == "string"
			   and .repo != "" and .ref != ""
			then "k " + .repo + " " + .ref
			# A record with no usable identity is its own group. Grouping these
			# together would coalesce unrelated malformed records into one
			# another and suppress the validation failure each one is owed.
			else "u " + (.__i | tostring)
			end
		)
		| map(
			. as $group
			| ($group | map(.__i)) as $slots
			| ($group | last) as $newest
			| ($group[0:-1]) as $displaced
			| [ {i: $slots[0], r: ($newest | del(.__i))} ]
			  + [ range(0; ($displaced | length)) as $n
			      | {i: $slots[$n + 1], r: (($displaced[$n] | del(.__i)) + {superseded: true})} ]
		)
		| flatten
		| sort_by(.i)
		| .[].r
	'
}

# Partition queued records for operator-initiated cancellation. Mode `match`
# emits the records a query selects; `exclude` emits the survivors. The two are
# exact complements, which is what lets a caller rewrite the queue and report
# what it removed without scanning twice with different logic.
#
# An empty branch or commit is a wildcard, but an empty project is NOT: a query
# must name a project, so a typo can never widen into "cancel everything".
# Project and branch compare exactly rather than by prefix, so dropping `z7` can
# never take `z7z`; only the commit is a prefix, matching how humans quote SHAs.
select_queue_records() {
	local mode="${1:-}"
	local project="${2:-}"
	local branch="${3:-}"
	local commit="${4:-}"
	local negate=false
	case "$mode" in
		match) ;;
		exclude) negate=true ;;
		*) return 1 ;;
	esac
	[ -n "$project" ] || return 1
	# Accept `name` or `owner/name`, and `branch` or `refs/heads/branch`.
	project="${project##*/}"
	branch="${branch#refs/heads/}"
	jq -c \
		--arg project "$project" \
		--arg branch "$branch" \
		--arg commit "$commit" \
		--argjson negate "$negate" '
		def matches:
			((.repo // "") | split("/") | last) == $project
			and ($branch == "" or ((.ref // "") | ltrimstr("refs/heads/")) == $branch)
			and ($commit == "" or ((.sha // "") | startswith($commit)));
		select((matches) != $negate)
	'
}

# Decide whether a build exit status means the build was stopped rather than
# that it ran and failed. `timeout` reports 124 when it fires, and reports
# 128+N when the command died on signal N (137 for SIGKILL, which is what an
# out-of-memory kill looks like). Neither outcome observed the project's code,
# so neither may be reported as a failing build.
build_exit_was_stopped() {
	local code="${1:-}"
	case "$code" in
		''|*[!0-9]*) return 1 ;;
	esac
	[ "$code" -eq 124 ] && return 0
	[ "$code" -ge 128 ] && return 0
	return 1
}

badge_json() {
	local state="${1:-}"
	local color
	local is_error=false
	case "$state" in
		UNKNOWN) color=lightgrey ;;
		BUILDING) color=blue ;;
		PASSING) color=brightgreen ;;
		FAILING)
			color=red
			is_error=true
			;;
		# A stopped build never ran to completion, so it is not evidence that
		# the project's code is broken. Amber, and deliberately not isError:
		# the condition belongs to this host, not to the repository.
		STOPPED) color=orange ;;
		# A superseded commit was displaced in the queue by a newer commit on
		# the same branch and will never build. Also not an error: it is a
		# scheduling outcome, and the commit that replaced it carries the
		# repository's real verdict.
		SUPERSEDED) color=orange ;;
		# An operator removed this commit from the queue before it ran. Like
		# the two above it is not an error: it says a human made a scheduling
		# decision, and it is deliberately distinct from SUPERSEDED so history
		# shows whether a commit was displaced automatically or dropped on
		# purpose.
		CANCELLED) color=orange ;;
		*) return 1 ;;
	esac
	jq -cn \
		--arg message "$state" \
		--arg color "$color" \
		--argjson isError "$is_error" \
		'{schemaVersion:1,label:"🤖 Mechatron Prime",message:$message,color:$color,isError:$isError}'
}

# Publish one complete Shields document with a same-directory atomic rename.
write_badge_document() {
	local destination="${1:-}"
	local state="${2:-}"
	local destination_dir
	local destination_name
	local temporary
	destination_dir="$(dirname "$destination")" || return 1
	destination_name="$(basename "$destination")" || return 1
	[ -d "$destination_dir" ] || return 1
	temporary="$(mktemp "$destination_dir/.${destination_name}.XXXXXX")" || return 1
	if ! badge_json "$state" > "$temporary"; then
		rm -f "$temporary"
		return 1
	fi
	chmod 0640 "$temporary" || {
		rm -f "$temporary"
		return 1
	}
	mv -f "$temporary" "$destination"
}

# Publish only the commit-addressable badge, leaving the repository's latest
# projection alone. Used for outcomes that describe a single commit without
# describing the repository's current state — a superseded commit never ran, so
# it must not overwrite the verdict of whatever actually built.
write_commit_badge_status() {
	local badge_dir="${1:-}"
	local repo="${2:-}"
	local state="${3:-}"
	local sha="${4:-}"
	local repo_name
	repo_name="$(repo_name_from_full_name "$repo")" || return 1
	[ -d "$badge_dir" ] || return 1
	[ -n "$sha" ] || return 1
	valid_commit_sha "$sha" || return 1
	[ -d "$badge_dir/$repo_name" ] || mkdir -m 0750 "$badge_dir/$repo_name" || return 1
	write_badge_document "$badge_dir/$repo_name/$sha.json" "$state"
}

# Publish the mutable latest badge plus an optional immutable commit address.
# The commit projection lands first so a successful latest update never points
# at a result whose historical document is missing.
write_badge_status() {
	local badge_dir="${1:-}"
	local repo="${2:-}"
	local state="${3:-}"
	local sha="${4:-}"
	local repo_name
	repo_name="$(repo_name_from_full_name "$repo")" || return 1
	[ -d "$badge_dir" ] || return 1
	if [ -n "$sha" ]; then
		valid_commit_sha "$sha" || return 1
		[ -d "$badge_dir/$repo_name" ] || mkdir -m 0750 "$badge_dir/$repo_name" || return 1
		write_badge_document "$badge_dir/$repo_name/$sha.json" "$state" || return 1
	fi
	write_badge_document "$badge_dir/$repo_name.json" "$state"
}
