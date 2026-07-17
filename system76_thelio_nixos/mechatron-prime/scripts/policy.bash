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
		*) return 1 ;;
	esac
	jq -cn \
		--arg message "$state" \
		--arg color "$color" \
		--argjson isError "$is_error" \
		'{schemaVersion:1,label:"🤖 Mechatron Prime",message:$message,color:$color,isError:$isError}'
}

# Publish a complete Shields document with a same-directory atomic rename.
write_badge_status() {
	local badge_dir="${1:-}"
	local repo="${2:-}"
	local state="${3:-}"
	local repo_name
	local temporary
	repo_name="$(repo_name_from_full_name "$repo")" || return 1
	[ -d "$badge_dir" ] || return 1
	temporary="$(mktemp "$badge_dir/.${repo_name}.json.XXXXXX")" || return 1
	if ! badge_json "$state" > "$temporary"; then
		rm -f "$temporary"
		return 1
	fi
	chmod 0640 "$temporary" || {
		rm -f "$temporary"
		return 1
	}
	mv -f "$temporary" "$badge_dir/$repo_name.json"
}
