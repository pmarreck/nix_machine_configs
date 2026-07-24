local cjson = require("cjson.safe")
local health = require("ops.health")
local probes = require("ops.probes")

local M = {}

local service_specs = {
	{scope = "system", unit = "NetworkManager.service", id = "network-manager", label = "NetworkManager", expected = "active", severity = "critical", detail = "wired and wireless network orchestration"},
	{scope = "system", unit = "tailscaled.service", id = "tailscale", label = "Tailscale", expected = "active", severity = "critical", detail = "tailnet connectivity"},
	{scope = "system", unit = "atticd.service", id = "attic", label = "Attic cache", expected = "active", severity = "warning", detail = "tailnet-local binary cache"},
	{scope = "system", unit = "ollama.service", id = "ollama", label = "Ollama", expected = "active", severity = "warning", detail = "local embedding service", model_inventory = true},
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
	{probe = "codex_remote_control", id = "codex-remote-control", label = "Codex remote-control", expected = "active", health = false, detail = "experimental remote app-server daemon", actions = {
		{label = "Check status", path = "/ops/actions/codex-remote-control/status"},
		{label = "Start", path = "/ops/actions/codex-remote-control/start"},
		{label = "Stop", path = "/ops/actions/codex-remote-control/stop", danger = true},
		{label = "Restart", path = "/ops/actions/codex-remote-control/restart", danger = true},
		{label = "Pair", path = "/ops/actions/codex-remote-control/pair"},
	}},
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

local function format_pools(pools, root_properties, scans)
	local lines = {}
	for _, pool in ipairs(pools) do
		lines[#lines + 1] = string.format("%-8s %-8s capacity %s · free %s · fragmentation %s", pool.name, pool.health, pool.capacity, pool.free, pool.fragmentation)
		local properties = root_properties[pool.name]
		if properties then
			lines[#lines + 1] = string.format("  compression %s · compressratio %s", properties.compression, properties.compressratio)
		end
		local scan = scans[pool.name]
		if scan then
			if scan.kind == "resilver" then
				lines[#lines + 1] = "  Last resilver: " .. scan.result .. (scan.completed_at and " · completed " .. scan.completed_at or "")
			elseif scan.kind == "resilvering" then
				lines[#lines + 1] = "  Resilver in progress: " .. scan.result
			else
				lines[#lines + 1] = "  Last resilver: not reported · latest scan: " .. scan.result .. (scan.completed_at and " · completed " .. scan.completed_at or "")
			end
		end
	end
	return table.concat(lines, "\n")
end

local function collect_mechatron(source)
	local queue_text = source.read("/var/lib/mechatron-prime/queue/builds.ndjson") or ""
	local current_text = source.read("/var/lib/mechatron-prime/current.json")
	local control_text = source.read("/var/lib/mechatron-prime/control.json")
	local control = control_text and cjson.decode(control_text) or nil
	local admission = {state = "running", changed_at = ""}
	if control and (control.state == "running" or control.state == "halted") then
		admission = {state = control.state, changed_at = control.changed_at or ""}
	elseif control_text then
		admission = {state = "unknown", changed_at = ""}
	end
	local worker_state = source.service("system", "mechatron-prime-worker.service")
	local current = nil
	-- A running Type=oneshot unit reports `activating` until its process exits.
	-- Treat it as live work so the operations console does not call an active
	-- build idle merely because it has not reached systemd's `active` state.
	if (worker_state == "active" or worker_state == "activating") and current_text and current_text:match("%S") then
		local decoded = cjson.decode(current_text)
		if decoded and decoded.state == "building" then current = decoded end
	end
	return {
		admission = admission,
		worker_state = worker_state,
		current = current,
		queue_depth = probes.count_ndjson(queue_text),
		recent = source.recent_ci_runs and source.recent_ci_runs() or {},
	}
end

--- Assemble one immutable UI model from injected host adapters; parsing and
--- classification stay deterministic while I/O remains replaceable in tests.
function M.collect(source)
	local services = {}
	local health_services = {}
	for _, spec in ipairs(service_specs) do
		local state = spec.probe and source[spec.probe]() or source.service(spec.scope, spec.unit)
		local service = {id = spec.id, label = spec.label, state = state, detail = spec.detail, actions = spec.actions}
		if spec.model_inventory then
			local models = probes.parse_ollama_models(source.run("ollama_tags") or "")
			local loaded_models = probes.parse_ollama_loaded_models(source.run("ollama_ps") or "")
			service.models = models or {}
			service.model_inventory_available = models ~= nil
			service.loaded_models = loaded_models or {}
			service.loaded_models_available = loaded_models ~= nil
			local inventory_detail = models and #models .. " installed models" or "model inventory unavailable"
			local residency_detail = loaded_models and #loaded_models .. " loaded" or "loaded state unavailable"
			service.detail = spec.detail .. " · " .. inventory_detail .. " · " .. residency_detail
		end
		services[#services + 1] = service
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
	local root_properties = probes.parse_zfs_root_properties(source.run("zfs_datasets") or "")
	local scans = probes.parse_zpool_scan_records(zpool_status)
	local recent_errors = probes.parse_journal_errors(source.run("journal_errors"), 20)

	local mechatron = collect_mechatron(source)

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
		mechatron = mechatron,
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
			pools = format_pools(pools, root_properties, scans),
		},
		resources = {
			hogs = source.run("hogs") or "hogs probe unavailable",
			network_hogs = source.run("network_hogs") or "network-hogs probe unavailable",
			steam_shader = steam_shader_output == "" and "idle" or "active",
		},
		recent_errors = recent_errors,
	}
end

return M
