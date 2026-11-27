#!/usr/bin/env bash
# Shared, expiring host-wide admission lease for CI and direct local builds.
# Callers must hold the global flock while checking this state and claiming.

admission_drain_dir() {
	printf '%s\n' "${MECHATRON_ADMISSION_DIR:-/run/mechatron-prime}"
}

# Return 0 for an active lease, 1 when admission is open, and 2 for invalid
# state. Invalid state is fail-closed so corrupt control data cannot admit work.
admission_drain_active() {
	local dir="${1:-$(admission_drain_dir)}" now="${2:-${MECHATRON_NOW_EPOCH:-$(date -u +%s)}}" lease
	lease="$dir/drain.json"
	[[ "$now" =~ ^[0-9]+$ ]] || return 2
	[[ -e "$lease" ]] || return 1
	[[ -f "$lease" && ! -L "$lease" ]] || return 2
	# One explicit projection makes malformed JSON, extra value streams and type
	# coercions fail closed.
	jq -e -s 'length == 1 and
		.[0].schema == "mechatron-admission-drain/v1" and
		(.[0].lease_id | type == "string" and length > 0) and
		(.[0].owner | type == "string" and length > 0) and
		(.[0].created_at | type == "number" and . == floor and . >= 0) and
		(.[0].expires_at | type == "number" and . == floor) and
		(.[0].expires_at > .[0].created_at)' \
		"$lease" >/dev/null 2>&1 || return 2
	local expires
	expires=$(jq -er '.expires_at' "$lease") || return 2
	(( expires > now ))
}

# Open the stable root-owned lock inode. Admission clients need only a shared
# read lock; lease mutations request the exclusive read/write lock. The parent
# directory is root-owned and non-writable by clients.
admission_drain_lock() {
	local -n fd_out="$1"
	local mode="${2:-shared}" path
	path="$(admission_drain_dir)/admission.lock"
	[[ -f "$path" && ! -L "$path" ]] || return 1
	case "$mode" in
		shared) exec {fd_out}<"$path" || return 1; flock -s "$fd_out" || { exec {fd_out}<&-; return 1; } ;;
		exclusive) exec {fd_out}<>"$path" || return 1; flock -x "$fd_out" || { exec {fd_out}>&-; return 1; } ;;
		*) return 2 ;;
	esac
}

# These mutations require the caller to hold admission.lock. The lease is one
# expiring singleton; a new owner cannot replace another active lease.
admission_drain_begin() {
	local -n id_out="$1"
	local dir="$2" owner="$3" seconds="$4" now="$5" generated_id temporary
	[[ "$seconds" =~ ^[0-9]{1,5}$ ]] && (( seconds > 0 && seconds <= 86400 )) || return 2
	[[ "$now" =~ ^[0-9]+$ && -n "$owner" ]] || return 2
	local active_status=0
	admission_drain_active "$dir" "$now" || active_status=$?
	case "$active_status" in 0) return 3 ;; 1) ;; *) return 1 ;; esac
	generated_id=$(cat /proc/sys/kernel/random/uuid) || return 1
	temporary=$(mktemp "$dir/.drain.json.XXXXXX") || return 1
	if ! jq -cn --arg id "$generated_id" --arg owner "$owner" --argjson created "$now" \
		--argjson expires "$((now + seconds))" \
		'{schema:"mechatron-admission-drain/v1",lease_id:$id,owner:$owner,created_at:$created,expires_at:$expires}' > "$temporary"; then
		command rm -f -- "$temporary"
		return 1
	fi
	if ! chmod 0644 "$temporary" || ! mv -f -- "$temporary" "$dir/drain.json"; then
		command rm -f -- "$temporary"
		return 1
	fi
	# shellcheck disable=SC2034 # nameref assigns the caller's output variable
	id_out=$generated_id
}

admission_drain_end() {
	local dir="$1" lease_id="$2" owner="$3" lease="$1/drain.json" current_owner current_id
	[[ -f "$lease" && ! -L "$lease" ]] || return 1
	current_id=$(jq -er '.lease_id | strings | select(length > 0)' "$lease" 2>/dev/null) || return 1
	current_owner=$(jq -er '.owner | strings | select(length > 0)' "$lease" 2>/dev/null) || return 1
	[[ "$current_id" = "$lease_id" && "$current_owner" = "$owner" ]] || return 2
	command unlink -- "$lease"
}

admission_drain_report() {
	local dir="$1" now="$2" status=0 state="open" lease="$1/drain.json"
	admission_drain_active "$dir" "$now" || status=$?
	case "$status" in 0) state="draining" ;; 1) [[ -e "$lease" ]] && state="expired" ;; *) state="invalid" ;; esac
	if [[ "$state" = draining || "$state" = expired ]]; then
		jq -cn --arg state "$state" --argjson now "$now" \
			--slurpfile lease "$lease" \
			'{state:$state,lease_id:$lease[0].lease_id,owner:$lease[0].owner,created_at:$lease[0].created_at,expires_at:$lease[0].expires_at,remaining_seconds:([$lease[0].expires_at - $now,0]|max)}'
	else
		jq -cn --arg state "$state" '{state:$state}'
	fi
}
