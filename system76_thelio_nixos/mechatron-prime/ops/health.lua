local M = {}

local severity_rank = {
	ok = 0,
	warning = 1,
	critical = 2,
}

local default_thresholds = {
	memory_warning_percent = 10,
	memory_critical_percent = 5,
	disk_warning_percent = 85,
	disk_critical_percent = 95,
	cpu_warning_percent = 90,
	cpu_critical_percent = 98,
}

local function add_check(result, check)
	result.checks[#result.checks + 1] = check
	if check.severity ~= "ok" then
		result.issues[#result.issues + 1] = check
	end
end

local function threshold_severity(value, warning_limit, critical_limit, higher_is_worse)
	if higher_is_worse then
		if value >= critical_limit then
			return "critical"
		elseif value >= warning_limit then
			return "warning"
		end
	else
		if value <= critical_limit then
			return "critical"
		elseif value <= warning_limit then
			return "warning"
		end
	end
	return "ok"
end

--- Classify a complete host snapshot so no failing probe can be hidden by an
--- unrelated healthy one; the worst member controls the aggregate state.
function M.evaluate(snapshot, thresholds)
	thresholds = thresholds or default_thresholds
	local result = {
		status = "healthy",
		checks = {},
		issues = {},
	}

	for _, service in ipairs(snapshot.services or {}) do
		local severity = "ok"
		if service.state ~= service.expected then
			severity = service.severity or "warning"
		end
		add_check(result, {
			id = "service:" .. service.id,
			label = service.label,
			severity = severity,
			observed = service.state,
			expected = service.expected,
		})
	end

	local available = snapshot.memory.available_percent
	add_check(result, {
		id = "memory",
		label = "Available memory",
		severity = threshold_severity(
			available,
			thresholds.memory_warning_percent,
			thresholds.memory_critical_percent,
			false
		),
		observed = available,
	})

	for _, disk in ipairs(snapshot.disks or {}) do
		add_check(result, {
			id = "disk:" .. disk.mount,
			label = "Disk " .. disk.mount,
			severity = threshold_severity(
				disk.used_percent,
				thresholds.disk_warning_percent,
				thresholds.disk_critical_percent,
				true
			),
			observed = disk.used_percent,
		})
	end

	local cpu_used = snapshot.cpu.used_percent
	add_check(result, {
		id = "cpu",
		label = "CPU use",
		severity = threshold_severity(
			cpu_used,
			thresholds.cpu_warning_percent,
			thresholds.cpu_critical_percent,
			true
		),
		observed = cpu_used,
	})

	local zfs_severity = "warning"
	if snapshot.zfs.state == "healthy" then
		zfs_severity = "ok"
	elseif snapshot.zfs.state == "faulted" then
		zfs_severity = "critical"
	end
	add_check(result, {
		id = "zfs",
		label = "ZFS",
		severity = zfs_severity,
		observed = snapshot.zfs.state,
		detail = snapshot.zfs.detail,
	})

	local recent_errors = snapshot.journal.recent_errors or {}
	add_check(result, {
		id = "journal",
		label = "Recent system errors",
		severity = #recent_errors == 0 and "ok" or "warning",
		observed = #recent_errors,
		detail = recent_errors,
	})

	local worst_rank = 0
	for _, issue in ipairs(result.issues) do
		worst_rank = math.max(worst_rank, severity_rank[issue.severity] or 1)
	end
	if worst_rank == severity_rank.critical then
		result.status = "critical"
	elseif worst_rank == severity_rank.warning then
		result.status = "degraded"
	end

	return result
end

return M
