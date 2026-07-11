local cjson = require("cjson.safe")
local health = require("ops.health")
local probes = require("ops.probes")

local M = {}

local service_specs = {
	{scope = "system", unit = "NetworkManager.service", id = "network-manager", label = "NetworkManager", expected = "active", severity = "critical", detail = "wired and wireless network orchestration"},
	{scope = "system", unit = "tailscaled.service", id = "tailscale", label = "Tailscale", expected = "active", severity = "critical", detail = "tailnet connectivity"},
	{scope = "system", unit = "atticd.service", id = "attic", label = "Attic cache", expected = "active", severity = "warning", detail = "tailnet-local binary cache"},
	{scope = "system", unit = "mechatron-prime-webhook.service", id = "mechatron-webhook", label = "Mechatron webhook", expected = "active", severity = "critical", detail = "accepting signed GitHub pushes", actions = {
		{label = "Start", path = "/ops/actions/mechatron-webhook/start"},
		{label = "Stop", path = "/ops/actions/mechatron-webhook/stop", danger = true},
		{label = "Restart", path = "/ops/actions/mechatron-webhook/restart"},
	}},
	{scope = "system", unit = "mechatron-prime-badges.service", id = "mechatron-badges", label = "Mechatron badges", expected = "active", severity = "warning", detail = "read-only Shields status documents"},
	{scope = "system", unit = "mechatron-prime-worker.path", id = "mechatron-worker-path", label = "Mechatron queue watcher", expected = "active", severity = "critical", detail = "starts the sequential worker when work arrives"},
	{scope = "user", unit = "pipewire.service", id = "pipewire", label = "PipeWire", expected = "active", severity = "critical", detail = "audio graph"},
	{scope = "user", unit = "wireplumber.service", id = "wireplumber", label = "WirePlumber", expected = "active", severity = "critical", detail = "audio session policy"},
	{scope = "user", unit = "pipewire-pulse.service", id = "pipewire-pulse", label = "PipeWire PulseAudio", expected = "active", severity = "critical", detail = "desktop audio compatibility endpoint"},
	{scope = "user", unit = "rescuetime.service", id = "rescuetime", label = "RescueTime", expected = "active", severity = "warning", health = false, detail = "optional time tracker; billing issue unresolved"},
}

local function trim(text)
	return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function format_gib(kib)
	return string.format("%.0f GiB", kib / 1024 / 1024)
end

local function format_disks(disks)
	local parts = {}
	for _, disk in ipairs(disks) do parts[#parts + 1] = disk.mount .. " " .. disk.used_percent .. "%" end
	return table.concat(parts, " · ")
end

local function format_pools(pools)
	local lines = {}
	for _, pool in ipairs(pools) do
		lines[#lines + 1] = string.format("%-8s %-8s capacity %s · free %s · fragmentation %s", pool.name, pool.health, pool.capacity, pool.free, pool.fragmentation)
	end
	return table.concat(lines, "\n")
end

--- Assemble one immutable UI model from injected host adapters; parsing and
--- classification stay deterministic while I/O remains replaceable in tests.
function M.collect(source)
	local services = {}
	local health_services = {}
	for _, spec in ipairs(service_specs) do
		local state = source.service(spec.scope, spec.unit)
		services[#services + 1] = {id = spec.id, label = spec.label, state = state, detail = spec.detail, actions = spec.actions}
		if spec.health ~= false then
			health_services[#health_services + 1] = {id = spec.id, label = spec.label, state = state, expected = spec.expected, severity = spec.severity}
		end
	end

	local clocksound = source.timer("clocksound.timer")
	clocksound.schedule = "07:00–23:00 plus midnight"
	clocksound.source = "/etc/nixos/system76_thelio_nixos/configuration.nix:385"
	health_services[#health_services + 1] = {id = "clocksound-timer", label = "Grandfather clock timer", state = clocksound.state, expected = "waiting", severity = "warning"}

	local fsearch = source.timer("fsearch-update.timer")
	fsearch.schedule = "03:30 daily"
	health_services[#health_services + 1] = {id = "fsearch-timer", label = "FSearch database timer", state = fsearch.state, expected = "waiting", severity = "warning"}

	local memory = probes.parse_meminfo(assert(source.read("/proc/meminfo"), "cannot read meminfo"))
	local disks = probes.parse_df(source.run("df") or "")
	local cpu = {used_percent = probes.normalized_load_percent(source.read("/proc/loadavg") or "", source.cpu_count())}
	local zpool_summary = source.run("zpool_summary") or "ZFS status unavailable"
	local zpool_status = source.run("zpool_status") or ""
	local zfs_state = probes.classify_zfs(zpool_summary, zpool_status)
	local pools = probes.parse_zpool_list(source.run("zpool_list") or "")
	local recent_errors = probes.parse_journal_errors(source.run("journal_errors"))

	local queue_text = source.read("/var/lib/mechatron-prime/queue/builds.ndjson") or ""
	local current_text = source.read("/var/lib/mechatron-prime/current.json")
	local worker_state = source.service("system", "mechatron-prime-worker.service")
	local current = nil
	if worker_state == "active" and current_text and current_text:match("%S") then
		local decoded = cjson.decode(current_text)
		if decoded and decoded.state == "building" then current = decoded end
	end

	local health_result = health.evaluate({
		services = health_services,
		memory = memory,
		disks = disks,
		cpu = cpu,
		zfs = {state = zfs_state, detail = trim(zpool_summary)},
		journal = {recent_errors = recent_errors},
	})

	local steam_shader_output = trim(source.run("steam_shader"))
	return {
		generated_at = source.now(),
		health = health_result,
		services = services,
		mechatron = {
			worker_state = worker_state,
			current = current,
			queue_depth = probes.count_ndjson(queue_text),
		},
		clocksound = clocksound,
		fsearch = fsearch,
		os = {
			nixos_version = trim(source.run("nixos_version")),
			uptime = probes.format_uptime(source.read("/proc/uptime") or ""),
			memory = memory.available_percent .. "% available",
			memory_detail = format_gib(memory.available_kib) .. " available / " .. format_gib(memory.total_kib),
			disks = format_disks(disks),
		},
		zfs = {
			status = zfs_state,
			detail = trim(zpool_summary),
			pools = format_pools(pools),
		},
		resources = {
			hogs = source.run("hogs") or "hogs probe unavailable",
			network_hogs = source.run("network_hogs") or "Awaiting network-hogs collector",
			steam_shader = steam_shader_output == "" and "idle" or "active",
		},
		recent_errors = recent_errors,
	}
end

return M
