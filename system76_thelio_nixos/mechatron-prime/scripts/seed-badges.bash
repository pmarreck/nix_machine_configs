#!/usr/bin/env bash
# Repair only missing or nonconforming public badge documents from root-owned policy.
set -u

allowlist="${MECHATRON_REPOS_ALLOWLIST:-/etc/mechatron-prime/repos.allowlist}"
badge_dir="${MECHATRON_BADGE_DIR:-/var/lib/mechatron-prime-public/badges}"

badge_document_is_conforming() {
	local path="$1"
	jq -e '
		type == "object" and
		.schemaVersion == 1 and
		.label == "🤖 Mechatron Prime" and
		(
			[.message, .color, .isError] == ["UNKNOWN", "lightgrey", false] or
			[.message, .color, .isError] == ["BUILDING", "blue", false] or
			[.message, .color, .isError] == ["PASSING", "brightgreen", false] or
			[.message, .color, .isError] == ["FAILING", "red", true]
		)
	' "$path" >/dev/null 2>&1
}

[ -r "$allowlist" ] || {
	printf 'Badge seed allowlist is not readable\n' >&2
	exit 1
}
[ -d "$badge_dir" ] || {
	printf 'Badge seed directory is missing\n' >&2
	exit 1
}

declare -a repositories=()
declare -A seen=()
line_number=0
while IFS= read -r repo || [ -n "$repo" ]; do
	line_number=$((line_number + 1))
	case "$repo" in
		""|\#*) continue ;;
	esac
	if ! valid_repo_full_name "$repo"; then
		printf 'Invalid badge seed repository on allowlist line %d\n' "$line_number" >&2
		exit 1
	fi
	if [ -n "${seen[$repo]+present}" ]; then
		printf 'Duplicate badge seed repository on allowlist line %d\n' "$line_number" >&2
		exit 1
	fi
	seen[$repo]=1
	repositories+=("$repo")
done < "$allowlist"

[ "${#repositories[@]}" -gt 0 ] || {
	printf 'Badge seed allowlist is empty\n' >&2
	exit 1
}

for repo in "${repositories[@]}"; do
	repo_name="$(repo_name_from_full_name "$repo")" || exit 1
	badge_path="$badge_dir/$repo_name.json"
	if [ ! -L "$badge_path" ] && [ -f "$badge_path" ] && badge_document_is_conforming "$badge_path"; then
		continue
	fi
	write_badge_status "$badge_dir" "$repo" UNKNOWN || exit 1
done
