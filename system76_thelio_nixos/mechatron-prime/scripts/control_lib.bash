#!/usr/bin/env bash
# Persistent admission state and lossless queue recovery shared by the worker
# and its exact-allowlisted control helper.
if ! declare -F admission_drain_active >/dev/null; then
	# shellcheck disable=SC1091
	source "${BASH_SOURCE[0]%/*}/admission_drain.bash"
fi

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

# The persistent CI halt is separate from the cross-queue expiring drain.
# Return 0 only when new work may be admitted, 1 for a deliberate stop, and
# 255 when either control surface is invalid.
ci_admission_open() {
	local state_dir="${1:-}" state drain_status=0
	state="$(ci_admission_state "$state_dir")" || return 255
	[[ "$state" = running ]] || return 1
	if declare -F admission_drain_active >/dev/null; then
		admission_drain_active || drain_status=$?
		case "$drain_status" in 0) return 1 ;; 1) return 0 ;; *) return 255 ;; esac
	fi
	return 0
}

write_ci_admission() {
	local state_dir="${1:-}"
	local state="${2:-}"
	local changed_at="${3:-}"
	local control_file="$state_dir/control.json"
	local temporary
	local ownership_reference="$state_dir"
	[ -d "$state_dir" ] && [ -n "$changed_at" ] || return 1
	case "$state" in running|halted) ;; *) return 1 ;; esac
	if [ -e "$control_file" ]; then
		[ -f "$control_file" ] && [ ! -L "$control_file" ] || return 1
		ownership_reference="$control_file"
	fi
	temporary="$(mktemp "$state_dir/.control.json.XXXXXX")" || return 1
	if ! jq -cn --arg state "$state" --arg changed_at "$changed_at" \
		'{state:$state,changed_at:$changed_at}' > "$temporary"
	then
		rm -f "$temporary"
		return 1
	fi
	chown --reference="$ownership_reference" "$temporary" || { rm -f "$temporary"; return 1; }
	chmod 0640 "$temporary" || { rm -f "$temporary"; return 1; }
	mv -f "$temporary" "$control_file"
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

claim_pointer_file() {
	local state_dir="${1:-}"
	[ -n "$state_dir" ] || return 1
	printf '%s/claim.json\n' "$state_dir"
}

# Persist the in-progress claim so a SIGKILLed worker can recover exactly the
# unbuilt remainder. Presence of this file, not of a batch file, is the orphan
# marker: historical batches without one must stay inert.
write_claim_pointer() {
	local state_dir="${1:-}"
	local batch="${2:-}"
	local recovery_line="${3:-}"
	local pointer
	local temporary
	local ownership_reference="$state_dir"
	[ -d "$state_dir" ] && [ -n "$batch" ] || return 1
	case "$recovery_line" in ""|*[!0-9]*|0) return 1 ;; esac
	pointer="$(claim_pointer_file "$state_dir")" || return 1
	if [ -e "$pointer" ]; then
		[ -f "$pointer" ] && [ ! -L "$pointer" ] || return 1
		ownership_reference="$pointer"
	fi
	temporary="$(mktemp "$state_dir/.claim.json.XXXXXX")" || return 1
	if ! jq -cn --arg batch "$batch" --argjson recovery_line "$recovery_line" \
		'{batch:$batch,recovery_line:$recovery_line}' > "$temporary"
	then
		rm -f "$temporary"
		return 1
	fi
	chown --reference="$ownership_reference" "$temporary" || { rm -f "$temporary"; return 1; }
	chmod 0640 "$temporary" || { rm -f "$temporary"; return 1; }
	mv -f "$temporary" "$pointer"
}

clear_claim_pointer() {
	local state_dir="${1:-}"
	local pointer
	[ -n "$state_dir" ] || return 1
	pointer="$(claim_pointer_file "$state_dir")" || return 1
	rm -f -- "$pointer"
}

# Requeue the unbuilt remainder of a claimed batch left by a worker that never
# ran its interrupt trap. Delivery IDs already in the queue or already terminal
# in the ledger are skipped so recovery is exactly-once.
recover_orphaned_claim() {
	local state_dir="${1:-}"
	local queue_file="${2:-}"
	local queue_lock="${3:-}"
	local database="${4:-}"
	local pointer batch start_line temporary line delivery lookup_status recovery_error=false
	local -A seen=()
	[ -n "$state_dir" ] && [ -d "${queue_file%/*}" ] && [ -n "$queue_lock" ] || return 1
	pointer="$(claim_pointer_file "$state_dir")" || return 1
	[ -e "$pointer" ] || return 0
	[ -f "$pointer" ] && [ ! -L "$pointer" ] || return 1
	batch="$(jq -er '.batch | strings' "$pointer" 2>/dev/null)" || return 1
	start_line="$(jq -er '.recovery_line | numbers | floor' "$pointer" 2>/dev/null)" || return 1
	[ -n "$batch" ] || return 1
	case "$start_line" in ""|*[!0-9]*|0) return 1 ;; esac
	if [ ! -f "$batch" ] || [ -L "$batch" ]; then
		rm -f -- "$pointer"
		return 0
	fi
	temporary="$(mktemp "${queue_file}.recover.XXXXXX")" || return 1
	exec 8> "$queue_lock" || { rm -f "$temporary"; return 1; }
	flock 8 || { exec 8>&-; rm -f "$temporary"; return 1; }
	if [ -e "$queue_file" ]; then
		[ -f "$queue_file" ] && [ ! -L "$queue_file" ] || { exec 8>&-; rm -f "$temporary"; return 1; }
	else
		: > "$queue_file" || { exec 8>&-; rm -f "$temporary"; return 1; }
		chmod 0640 "$queue_file" || { exec 8>&-; rm -f "$temporary"; return 1; }
	fi
	if [ -s "$queue_file" ]; then
		while IFS= read -r delivery; do
			[ -n "$delivery" ] && seen["$delivery"]=1
		done < <(jq -r '.delivery // empty' "$queue_file")
	fi
	{
		while IFS= read -r line || [ -n "$line" ]; do
			[ -n "$line" ] || continue
			delivery="$(jq -r '.delivery // empty' <<< "$line" 2>/dev/null)" || continue
			[ -n "$delivery" ] || continue
			[ -z "${seen[$delivery]+x}" ] || continue
			if [ -n "$database" ] && declare -F ci_delivery_has_result >/dev/null; then
				if ci_delivery_has_result "$database" "$delivery"; then
					continue
				else
					lookup_status=$?
					if [ "$lookup_status" -ne 1 ]; then recovery_error=true; break; fi
				fi
			fi
			seen["$delivery"]=1
			printf '%s\n' "$line"
		done < <(tail -n "+$start_line" "$batch")
		cat "$queue_file"
	} > "$temporary" || { exec 8>&-; rm -f "$temporary"; return 1; }
	if [ "$recovery_error" = true ]; then exec 8>&-; rm -f -- "$temporary"; return 1; fi
	chmod 0640 "$temporary" || { exec 8>&-; rm -f "$temporary"; return 1; }
	mv -f "$temporary" "$queue_file" || { exec 8>&-; rm -f "$temporary"; return 1; }
	exec 8>&-
	rm -f -- "$pointer"
}
