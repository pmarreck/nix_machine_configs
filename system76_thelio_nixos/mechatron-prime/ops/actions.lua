local M = {}

local by_path = {
	["/ops/actions/mechatron-webhook/start"] = {id = "mechatron-webhook-start", scope = "system", unit = "mechatron-prime-webhook.service", verb = "start"},
	["/ops/actions/mechatron-webhook/stop"] = {id = "mechatron-webhook-stop", scope = "system", unit = "mechatron-prime-webhook.service", verb = "stop"},
	["/ops/actions/mechatron-webhook/restart"] = {id = "mechatron-webhook-restart", scope = "system", unit = "mechatron-prime-webhook.service", verb = "restart"},
	["/ops/actions/mechatron-worker/start"] = {id = "mechatron-worker-start", scope = "system", unit = "mechatron-prime-worker.service", verb = "start"},
	["/ops/actions/mechatron-worker/stop"] = {id = "mechatron-worker-stop", scope = "system", unit = "mechatron-prime-worker.service", verb = "stop"},
	["/ops/actions/fsearch/run"] = {id = "fsearch-run", scope = "user", unit = "fsearch-update.service", verb = "start"},
	["/ops/actions/codex-remote-control/start"] = {id = "codex-remote-control-start", kind = "codex-remote-control", verb = "start"},
	["/ops/actions/codex-remote-control/stop"] = {id = "codex-remote-control-stop", kind = "codex-remote-control", verb = "stop"},
	["/ops/actions/codex-remote-control/pair"] = {id = "codex-remote-control-pair", kind = "codex-remote-control", verb = "pair", present_result = true},
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
