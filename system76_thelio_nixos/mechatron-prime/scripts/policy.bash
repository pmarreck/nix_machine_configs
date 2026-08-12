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
