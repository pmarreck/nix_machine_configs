#!/usr/bin/env bash
# Shared monotonic deadline, not a fresh timeout for each build target.
job_budget_now() {
	local uptime rest
	IFS=' ' read -r uptime rest < /proc/uptime || return 1
	[[ "$uptime" =~ ^[0-9]+\.[0-9]+$ ]] || return 1
	printf '%s\n' "${uptime%%.*}"
}

job_budget_remaining() {
	local deadline="$1" now="$2"
	[[ "$deadline" =~ ^[0-9]{1,12}$ && "$now" =~ ^[0-9]{1,12}$ ]] || return 1
	if (( now >= deadline )); then printf '0\n'; return 124; fi
	printf '%s\n' "$((deadline-now))"
}

job_budget_slice() {
	local deadline="$1" cap="$2" remaining sampled_now
	[[ "$cap" =~ ^[0-9]{1,8}$ && "$cap" -gt 0 ]] || return 1
	sampled_now=$(job_budget_now) || return 1
	remaining=$(job_budget_remaining "$deadline" "$sampled_now") || return $?
	if (( remaining > cap )); then remaining=$cap; fi
	printf '%s\n' "$remaining"
}

job_budget_command() {
	local deadline="$1" cap="$2" remaining
	shift 2
	remaining=$(job_budget_slice "$deadline" "$cap") || return $?
	timeout --kill-after=5s "$remaining" "$@"
}

# The host selects this approval file; repository manifests cannot grant exceptions.
job_runtime_limit() {
	local requested="$1" repo="$2" policy="$3" baseline
	[[ "$requested" =~ ^[0-9]{1,8}$ && "$requested" -gt 0 ]] || return 1
	baseline=$requested; if (( baseline > 1800 )); then baseline=1800; fi
	if [[ ! -e "$policy" ]]; then printf '%s\n' "$baseline"; return 0; fi
	[[ -f "$policy" ]] || return 1
	jq -er --arg repo "$repo" --argjson baseline "$baseline" '
		if .schema != "mechatron-runtime-approvals/v1" or (.approvals | type) != "object" then error("invalid approval registry")
		elif .approvals[$repo] == null then $baseline
		else .approvals[$repo] | if .approved_by == "mechatron-prime" and (.reason | type) == "string" and (.reason | length) > 0
			and (.seconds | type) == "number" and .seconds == (.seconds | floor) and .seconds > 0 and .seconds <= 86400
			then .seconds else error("invalid runtime approval") end end' "$policy" 2>/dev/null
}
