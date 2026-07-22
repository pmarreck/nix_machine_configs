#!/usr/bin/env bash
# Persistent admission state and lossless queue recovery shared by the worker
# and its exact-allowlisted control helper.

ci_admission_state() {
	local state_dir="${1:-}"
	local control_file="$state_dir/control.json"
	local state
	[ -n "$state_dir" ] || return 1
	[ -e "$control_file" ] || { printf 'running\n'; return 0; }
	[ -f "$control_file" ] && [ ! -L "$control_file" ] || return 1
	state="$(jq -er '.state | strings' "$control_file" 2>/dev/null)" || return 1
	case "$state" in
		running|halted) printf '%s\n' "$state" ;;
		*) return 1 ;;
	esac
}

write_ci_admission() {
	local state_dir="${1:-}"
	local state="${2:-}"
	local changed_at="${3:-}"
	local temporary
	[ -d "$state_dir" ] && [ -n "$changed_at" ] || return 1
	case "$state" in running|halted) ;; *) return 1 ;; esac
	temporary="$(mktemp "$state_dir/.control.json.XXXXXX")" || return 1
	if ! jq -cn --arg state "$state" --arg changed_at "$changed_at" \
		'{state:$state,changed_at:$changed_at}' > "$temporary"
	then
		rm -f "$temporary"
		return 1
	fi
	chmod 0640 "$temporary" || { rm -f "$temporary"; return 1; }
	mv -f "$temporary" "$state_dir/control.json"
}

recover_claimed_batch() {
	local batch="${1:-}"
	local start_line="${2:-}"
	local queue_file="${3:-}"
	local queue_lock="${4:-}"
	local temporary
	[ -f "$batch" ] && [ -d "${queue_file%/*}" ] && [ -n "$queue_lock" ] || return 1
	case "$start_line" in ""|*[!0-9]*|0) return 1 ;; esac
	temporary="$(mktemp "${queue_file}.recover.XXXXXX")" || return 1
	exec 8> "$queue_lock" || { rm -f "$temporary"; return 1; }
	flock 8 || { exec 8>&-; rm -f "$temporary"; return 1; }
	if [ -e "$queue_file" ]; then
		[ -f "$queue_file" ] && [ ! -L "$queue_file" ] || { exec 8>&-; rm -f "$temporary"; return 1; }
	else
		: > "$queue_file" || { exec 8>&-; rm -f "$temporary"; return 1; }
		chmod 0640 "$queue_file" || { exec 8>&-; rm -f "$temporary"; return 1; }
	fi
	{
		tail -n "+$start_line" "$batch"
		cat "$queue_file"
	} > "$temporary" || { exec 8>&-; rm -f "$temporary"; return 1; }
	chmod 0640 "$temporary" || { exec 8>&-; rm -f "$temporary"; return 1; }
	mv -f "$temporary" "$queue_file" || { exec 8>&-; rm -f "$temporary"; return 1; }
	exec 8>&-
}
