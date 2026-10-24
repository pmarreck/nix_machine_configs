#!/usr/bin/env bash
# A host-selected, expiring priority class; FIFO order is stable within classes.
admission_priority_now() { date -u +%s; }

admission_priority_names() {
	local policy="$1" now="$2"
	[[ "$now" =~ ^[0-9]{1,12}$ ]] || return 2
	if [[ ! -e "$policy" ]]; then printf '[]\n'; return 0; fi
	jq -ce --argjson now "$now" '
		if .schema != "mechatron-scheduling/v1" or (.expires_at|type)!="number" or .expires_at!=(.expires_at|floor)
			or (.projects|type)!="array" or (.projects|length)>64
			or any(.projects[]; type!="string" or (test("^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")|not))
		then error("invalid scheduling policy")
		elif .expires_at <= $now then [] else (.projects|map(ascii_downcase)) end' "$policy" 2>/dev/null
}

prioritize_queue_batch() {
	local policy="$1" now="$2" names
	names=$(admission_priority_names "$policy" "$now") || return $?
	jq -Rrs --argjson names "$names" '
		split("\n") | to_entries | map(select(.value|length>0)) |
		sort_by(((try (.value|fromjson|.repo|split("/")|last|ascii_downcase) catch "") as $project |
			if ($names|index($project)) != null then 0 else 1 end), .key) | .[].value'
}
