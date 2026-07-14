#!/usr/bin/env bash
# Pure validation and badge rendering shared by the webhook receiver and worker.

valid_repo_full_name() {
	local repo="${1:-}"
	local name
	[[ "$repo" =~ ^pmarreck/[A-Za-z0-9._-]{1,100}$ ]] || return 1
	name="${repo#pmarreck/}"
	[ "$name" != "." ] && [ "$name" != ".." ]
}

repo_is_allowed() {
	local repo="${1:-}"
	local allowlist="${2:-}"
	local line
	valid_repo_full_name "$repo" || return 1
	[ -f "$allowlist" ] || return 1
	while IFS= read -r line; do
		case "$line" in
			""|\#*) continue ;;
		esac
		[ "$line" = "$repo" ] && return 0
	done < "$allowlist"
	return 1
}

repo_name_from_full_name() {
	local repo="${1:-}"
	valid_repo_full_name "$repo" || return 1
	printf '%s\n' "${repo#pmarreck/}"
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
	[[ "${1:-}" =~ ^refs/heads/[A-Za-z0-9._/-]{1,100}$ ]]
}

# Read an explicit repository-to-ref policy as a whole set before allowing a
# push, so fork branch conventions cannot weaken the default project policy.
repo_ref_is_allowed() {
	local repo="${1:-}"
	local ref="${2:-}"
	local refs_file="${3:-}"
	local line
	local configured_repo
	local configured_ref
	local extra
	local expected_ref=""
	local found=false

	valid_repo_full_name "$repo" || return 1
	valid_branch_ref "$ref" || return 1
	[ -f "$refs_file" ] || return 1
	while IFS= read -r line || [ -n "$line" ]; do
		IFS=$'\t' read -r configured_repo configured_ref extra <<< "$line"
		valid_repo_full_name "$configured_repo" || return 1
		valid_branch_ref "$configured_ref" || return 1
		[ -z "$extra" ] || return 1
		if [ "$configured_repo" = "$repo" ]; then
			[ "$found" = false ] || return 1
			expected_ref="$configured_ref"
			found=true
		fi
	done < "$refs_file"

	[ "$found" = true ] && [ "$ref" = "$expected_ref" ]
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
