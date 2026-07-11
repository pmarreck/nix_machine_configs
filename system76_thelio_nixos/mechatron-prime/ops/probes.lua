local M = {}

--- Parse Linux meminfo into scalar capacity facts used by both display and
--- threshold logic, preferring the kernel's reclaim-aware MemAvailable value.
function M.parse_meminfo(text)
	local values = {}
	for key, value in text:gmatch("([%a_]+):%s*(%d+)%s+kB") do
		values[key] = tonumber(value)
	end
	local total = assert(values.MemTotal, "MemTotal is missing")
	local available = assert(values.MemAvailable, "MemAvailable is missing")
	return {
		total_kib = total,
		available_kib = available,
		available_percent = math.floor((available * 100 / total) + 0.5),
	}
end

--- Parse POSIX `df -P` output as a filesystem set so every requested mount is
--- classified instead of relying on a presence check for one filesystem.
function M.parse_df(text)
	local disks = {}
	for line in text:gmatch("[^\n]+") do
		local filesystem, blocks, used, available, percent, mount = line:match("^(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%%%s+(.+)$")
		if filesystem then
			disks[#disks + 1] = {
				filesystem = filesystem,
				blocks_kib = tonumber(blocks),
				used_kib = tonumber(used),
				available_kib = tonumber(available),
				used_percent = tonumber(percent),
				mount = mount,
			}
		end
	end
	return disks
end

function M.format_uptime(text)
	local total_seconds = tonumber(text:match("^([%d.]+)")) or 0
	local total_minutes = math.floor(total_seconds / 60)
	local days = math.floor(total_minutes / 1440)
	local hours = math.floor((total_minutes % 1440) / 60)
	local minutes = total_minutes % 60
	local parts = {}
	if days > 0 then parts[#parts + 1] = days .. (days == 1 and " day" or " days") end
	if hours > 0 then parts[#parts + 1] = hours .. (hours == 1 and " hour" or " hours") end
	if days == 0 and minutes > 0 then parts[#parts + 1] = minutes .. (minutes == 1 and " minute" or " minutes") end
	if #parts == 0 then return "less than a minute" end
	return table.concat(parts, " ")
end

function M.parse_properties(text)
	local properties = {}
	for line in text:gmatch("[^\n]+") do
		local key, value = line:match("^([^=]+)=(.*)$")
		if key then properties[key] = value end
	end
	return properties
end

--- Parse the stable tab-separated ZFS list projection rather than scraping the
--- human column alignment used by interactive `zpool list` output.
function M.parse_zpool_list(text)
	local pools = {}
	for line in text:gmatch("[^\n]+") do
		local fields = {}
		for field in (line .. "\t"):gmatch("(.-)\t") do fields[#fields + 1] = field end
		if #fields >= 7 then
			pools[#pools + 1] = {
				name = fields[1],
				health = fields[2],
				size = fields[3],
				allocated = fields[4],
				free = fields[5],
				capacity = fields[6],
				fragmentation = fields[7],
			}
		end
	end
	return pools
end

function M.classify_zfs(summary, detail)
	local combined = (summary .. "\n" .. detail):lower()
	if combined:find("resilver in progress", 1, true) then return "resilvering" end
	if combined:find("scrub in progress", 1, true) then return "scrubbing" end
	if not summary:lower():find("all pools are healthy", 1, true) then return "faulted" end
	return "healthy"
end

function M.count_ndjson(text)
	local count = 0
	for line in text:gmatch("[^\n]+") do
		if line:match("%S") then count = count + 1 end
	end
	return count
end

function M.normalized_load_percent(loadavg, cpu_count)
	local load_one = tonumber(loadavg:match("^([%d.]+)")) or 0
	if cpu_count <= 0 then return 0 end
	return math.min(100, math.floor((load_one * 100 / cpu_count) + 0.5))
end

--- Decide whether a journal line is operationally notable, retaining primary
--- crash/failure records while discarding known probe noise and multiline
--- coredump detail that would otherwise crowd the bounded incident list.
function M.is_notable_journal_error(line)
	local lower = line:lower()
	if line == "-- No entries --" or lower:match("^hint:") or line:match("^%s") then return false end
	if lower:find("rescuetime", 1, true) then return false end
	if lower:find("sudo[", 1, true)
		and lower:find("a password is required", 1, true)
		and lower:match("command=.*[/ ]true%s*$") then
		return false
	end
	return line:match("%S") ~= nil
end

--- Parse a bounded newest-first incident view from journal output after
--- filtering harmless records, so noisy probes cannot evict a real crash.
function M.parse_journal_errors(text, limit)
	local errors = {}
	for line in (text or ""):gmatch("[^\n]+") do
		if M.is_notable_journal_error(line) then errors[#errors + 1] = line end
	end
	if limit and #errors > limit then
		local newest = {}
		for index = #errors - limit + 1, #errors do newest[#newest + 1] = errors[index] end
		return newest
	end
	return errors
end

return M
