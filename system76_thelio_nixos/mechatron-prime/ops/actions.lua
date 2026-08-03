local M = {}

local by_path = {
	["/ops/actions/mechatron-webhook/start"] = {id = "mechatron-webhook-start", scope = "system", unit = "mechatron-prime-webhook.service", verb = "start"},
	["/ops/actions/mechatron-webhook/stop"] = {id = "mechatron-webhook-stop", scope = "system", unit = "mechatron-prime-webhook.service", verb = "stop"},
	["/ops/actions/mechatron-webhook/restart"] = {id = "mechatron-webhook-restart", scope = "system", unit = "mechatron-prime-webhook.service", verb = "restart"},
	["/ops/actions/mechatron-worker/start"] = {id = "mechatron-worker-start", scope = "system", unit = "mechatron-prime-worker.service", verb = "start"},
	["/ops/actions/mechatron-worker/stop"] = {id = "mechatron-worker-stop", scope = "system", unit = "mechatron-prime-worker.service", verb = "stop"},
	["/ops/actions/mechatron-worker/halt"] = {id = "mechatron-worker-halt", kind = "mechatron", argv = {"halt"}},
	["/ops/actions/mechatron-worker/resume"] = {id = "mechatron-worker-resume", kind = "mechatron", argv = {"resume"}},
	["/ops/actions/fsearch/run"] = {id = "fsearch-run", scope = "user", unit = "fsearch-update.service", verb = "start"},
	-- The chime controls change only the timer's RUN state, never its schedule,
	-- which stays owned by NixOS. `mask` is a durable override that outlives a
	-- reboot and a NixOS activation; a plain `stop` lasts only until the next
	-- boot re-arms the timer. Verbs are fixed here and the unit name lives in
	-- the adapter, so no part of either is derivable from a request.
	["/ops/actions/clocksound/mute-until-reboot"] = {id = "clocksound-mute-until-reboot", kind = "clocksound", steps = {{"stop"}}},
	["/ops/actions/clocksound/mute"] = {id = "clocksound-mute", kind = "clocksound", steps = {{"mask", "--now"}}},
	["/ops/actions/clocksound/unmute"] = {id = "clocksound-unmute", kind = "clocksound", steps = {{"unmask"}, {"start"}}},
	["/ops/actions/codex-remote-control/status"] = {id = "codex-remote-control-status", kind = "codex", argv = {"app-server", "daemon", "version"}, present_result = true},
	["/ops/actions/codex-remote-control/start"] = {id = "codex-remote-control-start", kind = "codex", argv = {"remote-control", "start", "--json"}, present_result = true},
	["/ops/actions/codex-remote-control/stop"] = {id = "codex-remote-control-stop", kind = "codex", argv = {"remote-control", "stop", "--json"}},
	["/ops/actions/codex-remote-control/restart"] = {id = "codex-remote-control-restart", kind = "codex", argv = {"app-server", "daemon", "restart"}},
	["/ops/actions/codex-remote-control/pair"] = {id = "codex-remote-control-pair", kind = "codex", argv = {"remote-control", "pair", "--json"}, present_result = true},
}

local by_id = {}
for _, action in pairs(by_path) do
	by_id[action.id] = action
end

--- Resolve controls by exact path so request text can never become a systemd
--- unit name, verb, option, or shell fragment.
function M.resolve(path)
	return by_path[path]
end

function M.resolve_id(id)
	return by_id[id]
end

function M.all()
	local result = {}
	for path, action in pairs(by_path) do
		result[#result + 1] = {path = path, action = action}
	end
	table.sort(result, function(left, right)
		return left.path < right.path
	end)
	return result
end

return M
