local cjson = require("cjson.safe")

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

--- Accept only the fixed `/api/tags` model set so the page can show Ollama's
--- actual local inventory without treating malformed or partial JSON as fact.
function M.parse_ollama_models(text)
	local decoded = cjson.decode(text or "")
	if type(decoded) ~= "table" or type(decoded.models) ~= "table" then return nil end
	local models = {}
	for _, candidate in ipairs(decoded.models) do
		if type(candidate) ~= "table" or type(candidate.name) ~= "string" or candidate.name == "" then return nil end
		local size = tonumber(candidate.size)
		models[#models + 1] = {name = candidate.name, size = size}
	end
	return models
end

--- `/api/ps` uses the same bounded model-set shape as `/api/tags`, but it
--- reports only models currently resident in Ollama.  Keep this separate at
--- the call site so an unavailable residency probe is never presented as an
--- empty resident set.
function M.parse_ollama_loaded_models(text)
	return M.parse_ollama_models(text)
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

--- Read root-dataset compression facts from a tabular ZFS projection, keeping
--- child datasets out so each pool card reports its own effective baseline.
function M.parse_zfs_root_properties(text)
	local properties = {}
	for line in text:gmatch("[^\n]+") do
		local name, compression, compressratio = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)$")
		if name and not name:find("/", 1, true) then
			properties[name] = {compression = compression, compressratio = compressratio}
		end
	end
	return properties
end

--- Associate each pool's latest `zpool status` scan with its result and
--- completion time, preserving the crucial scrub-versus-resilver distinction.
function M.parse_zpool_scan_records(text)
	local records = {}
	local pool = nil
	for line in text:gmatch("[^\n]+") do
		local found_pool = line:match("^%s*pool:%s*(%S+)")
		if found_pool then
			pool = found_pool
		else
			local scan = pool and line:match("^%s*scan:%s*(.+)$")
			if scan then
				local result, completed_at = scan:match("^(.-)%s+on%s+(.+)$")
				result = result or scan
				local lower = result:lower()
				local kind = lower:match("^scrub") and "scrub"
					or lower:match("^resilvered") and "resilver"
					or lower:match("^resilver in progress") and "resilvering"
				if kind then records[pool] = {kind = kind, result = result, completed_at = completed_at} end
			end
		end
	end
	return records
end

function M.classify_zfs(summary, detail)
	local combined = (summary .. "\n" .. detail):lower()
	if combined:find("resilver in progress", 1, true) then return "resilvering" end
	if combined:find("scrub in progress", 1, true) then return "scrubbing" end
	if not summary:lower():find("all pools are healthy", 1, true) then return "faulted" end
	return "healthy"
end

local chime_specs = {
	chiming = {label = "chiming", healthy = true},
	muted = {label = "muted", healthy = true},
	["muted-till-reboot"] = {label = "muted till reboot", healthy = true},
	failed = {label = "failed", healthy = false},
	unknown = {label = "unknown", healthy = false},
}

--- Classify the grandfather-clock timer from systemd's own load and run state,
--- separating a deliberate operator mute from a genuine fault so muting the
--- chime never degrades host health.  Load state is consulted FIRST because
--- masking an active unit leaves it reporting ActiveState=failed: checking run
--- state first would report every durable mute as a failure.  A masked unit is
--- muted durably (the mask outlives reboot and NixOS activation); a merely
--- stopped unit is muted only until the next boot re-arms it.
function M.classify_chime(load_state, active_state)
	load_state = load_state or ""
	active_state = active_state or ""
	local state
	if load_state == "masked" then
		state = "muted"
	elseif load_state ~= "loaded" then
		state = "unknown"
	elseif active_state == "active" or active_state == "activating" then
		state = "chiming"
	elseif active_state == "inactive" or active_state == "deactivating" then
		state = "muted-till-reboot"
	elseif active_state == "failed" then
		state = "failed"
	else
		state = "unknown"
	end
	local spec = chime_specs[state]
	return {state = state, label = spec.label, healthy = spec.healthy}
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
	if lower:find("dbus-broker-launch", 1, true) and lower:find("ignoring duplicate name", 1, true) then return false end
	if lower:find("sudo[", 1, true)
		and (lower:find("pam_unix(sudo:auth): conversation failed", 1, true)
			or lower:find("pam_unix(sudo:auth): auth could not identify password for [pmarreck]", 1, true)) then
		return false
	end
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
