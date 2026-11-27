#!/usr/bin/env bash
# A lane claims one eligible FIFO item, retaining an exclusive repository lease.
queue_commit_effect() { mv -f -- "$1" "$2"; }

# The lifecycle gate precedes the queue lock everywhere. A peer that is still
# exiting retains its identity reservation even after releasing its repository.
recover_idle_lanes_locked() {
	local state="$1" queue="$2" lock="$3" database="$4" lane peer status
	for lane in 1 2; do
		[[ -e "$state/workers/$lane/claim.json" ]] || continue
		exec {peer}> "$state/workers/$lane/.running.lock" || return 1
		if flock -n -E 75 "$peer"; then
			if ! recover_orphaned_claim "$state/workers/$lane" "$queue" "$lock" "$database"; then exec {peer}>&-; return 1; fi
		else
			status=$?
			if [[ "$status" -ne 75 ]]; then exec {peer}>&-; return 1; fi
		fi
		exec {peer}>&-
	done
}

# Nameref outputs transfer the lease FD to the caller.
# shellcheck disable=SC2034
worker_lane_begin() {
	local -n selected_lane="$1"
	local state="$2" lane="$3" queue="$4" lock="$5" database="$6" lifecycle running status
	selected_lane=''
	case "$lane" in 1|2) ;; *) return 2 ;; esac
	mkdir -p "$state/workers/1" "$state/workers/2" || return 1
	exec {lifecycle}> "$state/.lifecycle.lock" || return 1
	if ! flock "$lifecycle"; then exec {lifecycle}>&-; return 1; fi
	if ! recover_idle_lanes_locked "$state" "$queue" "$lock" "$database"; then exec {lifecycle}>&-; return 1; fi
	exec {running}> "$state/workers/$lane/.running.lock" || { exec {lifecycle}>&-; return 1; }
	if flock -n -E 75 "$running"; then
		selected_lane=$running; exec {lifecycle}>&-; return 0
	else status=$?; fi
	exec {running}>&-; exec {lifecycle}>&-
	return "$status"
}

queue_record_reserved() {
	local state="$1" item="$2" lane pointer batch cursor other delivery other_delivery
	delivery=$(jq -er '.delivery | strings | select(length>0)' <<< "$item" 2>/dev/null) || delivery=''
	for lane in 1 2; do
		pointer="$state/workers/$lane/claim.json"
		[[ -e "$pointer" ]] || continue
		batch=$(jq -er '.batch | strings' "$pointer" 2>/dev/null) || { [[ ! -e "$pointer" ]] && continue; return 2; }
		cursor=$(jq -er '.recovery_line | select(type=="number" and .==floor and .>0)' "$pointer" 2>/dev/null) || { [[ ! -e "$pointer" ]] && continue; return 2; }
		[[ "$cursor" -eq 1 ]] || continue
		[[ -f "$batch" && ! -L "$batch" ]] || return 2
		# Nothing in a batch has run at cursor 1, so every line is still reserved.
		while IFS= read -r other || [[ -n "$other" ]]; do
			other_delivery=$(jq -er '.delivery | strings | select(length>0)' <<< "$other" 2>/dev/null) || other_delivery=''
			if [[ -n "$delivery" && "$delivery" = "$other_delivery" ]] || [[ "$item" = "$other" ]]; then return 0; fi
		done < "$batch"
	done
	return 1
}

# shellcheck disable=SC2034
claim_fifo_job() {
	local -n selected_lease="$1"
	local state="$2" queue="$3" lock="$4" batch="$5" claims="$6"
	local gate lifecycle collapsed ordered remainder settled item repo key candidate delivery verdict held='' picked=false consumed=false status=0 admission_gate drain_status
	local picked_item='' picked_group='' indexed=false annotated parts index=''
	local -a drops=()
	selected_lease=''
	declare -F ci_delivery_has_result >/dev/null || return 1
	mkdir -p "$state/leases" "$claims" || return 1
	admission_drain_lock admission_gate shared || return 1
	exec {lifecycle}> "$state/.lifecycle.lock" || { exec {admission_gate}<&-; return 1; }
	if ! flock "$lifecycle"; then exec {lifecycle}>&-; exec {admission_gate}<&-; return 1; fi
	if ! recover_idle_lanes_locked "$state" "$queue" "$lock" "$state/results.sqlite3"; then exec {lifecycle}>&-; exec {admission_gate}<&-; return 1; fi
	exec {gate}> "$lock" || { exec {lifecycle}>&-; exec {admission_gate}<&-; return 1; }
	if ! flock "$gate"; then exec {gate}>&-; exec {lifecycle}>&-; exec {admission_gate}<&-; return 1; fi
	drain_status=0
	admission_drain_active || drain_status=$?
	if [[ "$drain_status" -eq 0 ]]; then
		exec {admission_gate}<&-; exec {gate}>&-; exec {lifecycle}>&-
		return 4
	elif [[ "$drain_status" -ne 1 ]]; then
		exec {admission_gate}<&-; exec {gate}>&-; exec {lifecycle}>&-
		return 1
	fi
	if [[ ! -s "$queue" ]]; then exec {admission_gate}<&-; exec {gate}>&-; exec {lifecycle}>&-; return 3; fi
	collapsed=$(mktemp "$queue.candidates.XXXXXX") || { exec {admission_gate}<&-; exec {gate}>&-; exec {lifecycle}>&-; return 1; }
	remainder=$(mktemp "$queue.remaining.XXXXXX") || { rm -f -- "$collapsed"; exec {admission_gate}<&-; exec {gate}>&-; exec {lifecycle}>&-; return 1; }
	settled=$(mktemp "$queue.settled.XXXXXX") || { rm -f -- "$collapsed" "$remainder"; exec {admission_gate}<&-; exec {gate}>&-; exec {lifecycle}>&-; return 1; }
	# Collapse only to choose; the queue itself keeps arrival order. Each record
	# carries its arrival index (__q), so the queue can be rewritten from the
	# original records. Persisting the collapsed order instead made a later
	# claim read the moved-up newest commit as the oldest and supersede it.
	if annotated=$(jq -c -s 'to_entries[] | .value + {__q: .key}' < "$queue" 2>/dev/null) \
			&& collapse_queue_batch <<< "$annotated" > "$collapsed" 2>/dev/null; then
		indexed=true
	else
		cp -- "$queue" "$collapsed" || status=1
	fi
	if [[ "$status" -eq 0 ]] && declare -F prioritize_queue_batch >/dev/null; then
		ordered=$(mktemp "$queue.priority.XXXXXX") || status=1
		if [[ "$status" -eq 0 ]]; then
			if prioritize_queue_batch "${MECHATRON_SCHEDULING_FILE:-/etc/mechatron-prime/scheduling.json}" "$(admission_priority_now)" < "$collapsed" > "$ordered"; then
				mv -f -- "$ordered" "$collapsed" || status=1
			else status=1; fi
			rm -f -- "$ordered"
		fi
	fi
	if [[ "$status" -eq 0 ]]; then
		while IFS= read -r item || [[ -n "$item" ]]; do
			[[ -n "$item" ]] || continue
			if [[ "$indexed" = true ]]; then
				parts=$(jq -rc '(.__q | tostring) + " " + (del(.__q) | tojson)' <<< "$item") || { status=1; break; }
				index=${parts%% *}; item=${parts#* }
			fi
			if [[ "$picked" = false ]]; then
				delivery=$(jq -er '.delivery | strings | select(length>0)' <<< "$item" 2>/dev/null) || delivery=''
				if [[ -n "$delivery" ]]; then
					if ci_delivery_has_result "$state/results.sqlite3" "$delivery"; then consumed=true; drops+=("$index"); continue; else verdict=$?; fi
					if [[ "$verdict" -ne 1 ]]; then status=1; break; fi
				fi
				if queue_record_reserved "$state" "$item"; then
					[[ "$indexed" = true ]] || printf '%s\n' "$item" >> "$remainder" || { status=1; break; }
					continue
				else verdict=$?; fi
				if [[ "$verdict" -ne 1 ]]; then status=1; break; fi
				repo=$(jq -er '.repo | strings' <<< "$item" 2>/dev/null) || repo=''
				# Invalid records still get terminal handling, without deriving paths from them.
				key="invalid-${claims##*/}"
				if [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
					# GitHub repository identity is case-insensitive. Hash only the
					# canonical lease key; preserve the exact event text in the claim.
					key=$(printf '%s' "${repo,,}" | sha256sum) || { status=1; break; }
					key=${key%% *}
				fi
				exec {candidate}> "$state/leases/$key.lock" || { status=1; break; }
				if flock -n -E 75 "$candidate"; then
					if [[ -n "$delivery" ]]; then
						if ci_delivery_has_result "$state/results.sqlite3" "$delivery"; then
							consumed=true; drops+=("$index"); exec {candidate}>&-; continue
						else verdict=$?; fi
						if [[ "$verdict" -ne 1 ]]; then exec {candidate}>&-; status=1; break; fi
					fi
					held=$candidate
					picked_item=$item
					picked_group=$(jq -c '[.repo, .ref]' <<< "$item" 2>/dev/null) || picked_group=''
					picked=true
					drops+=("$index")
					continue
				else
					status=$?
					exec {candidate}>&-
					if [[ "$status" -ne 75 ]]; then break; fi
					status=0
				fi
			# Commits this claim displaced settle with it, ahead of the build, so their
			# superseded verdicts do not wait behind every later build of the branch.
			elif [[ "$picked_group" = \[* ]] && jq -e --argjson group "$picked_group" \
					'.superseded == true and [.repo, .ref] == $group' <<< "$item" >/dev/null 2>&1; then
				delivery=$(jq -er '.delivery | strings | select(length>0)' <<< "$item" 2>/dev/null) || delivery=''
				if [[ -n "$delivery" ]]; then
					if ci_delivery_has_result "$state/results.sqlite3" "$delivery"; then consumed=true; drops+=("$index"); continue; else verdict=$?; fi
					if [[ "$verdict" -ne 1 ]]; then status=1; break; fi
				fi
				if queue_record_reserved "$state" "$item"; then :; else
					verdict=$?
					if [[ "$verdict" -ne 1 ]]; then status=1; break; fi
					printf '%s\n' "$item" >> "$settled" || { status=1; break; }
					drops+=("$index")
					continue
				fi
			fi
			[[ "$indexed" = true ]] || printf '%s\n' "$item" >> "$remainder" || { status=1; break; }
		done < "$collapsed"
	fi
	if [[ "$status" -eq 0 && "$indexed" = true ]]; then
		local drop_json
		drop_json="[$(printf '%s\n' "${drops[@]}" | paste -sd,)]"
		jq -c -s --argjson drop "$drop_json" \
			'to_entries[] | select(.key as $k | $drop | any(. == $k) | not) | .value | del(.superseded)' \
			< "$queue" > "$remainder" || status=1
	fi
	if [[ "$status" -eq 0 && "$picked" = true ]]; then
		# Recovery deduplicates against the queue if publication fails before rename.
		# The pointer must exist before the selected item disappears from the queue.
		{ cat -- "$settled" && printf '%s\n' "$picked_item"; } > "$batch" \
			&& chmod 0640 "$batch" "$remainder" && write_claim_pointer "$claims" "$batch" 1 \
			&& queue_commit_effect "$remainder" "$queue" || status=1
	elif [[ "$status" -eq 0 && "$consumed" = true ]]; then
		chmod 0640 "$remainder" && queue_commit_effect "$remainder" "$queue" || status=1
	fi
	rm -f -- "$collapsed" "$remainder" "$settled"
	exec {admission_gate}<&-
	exec {gate}>&-
	exec {lifecycle}>&-
	if [[ "$status" -ne 0 ]]; then
		if [[ -n "$held" ]]; then exec {held}>&-; fi
		return "$status"
	fi
	if [[ "$picked" = false ]]; then return 3; fi
	selected_lease=$held
	return 0
}
