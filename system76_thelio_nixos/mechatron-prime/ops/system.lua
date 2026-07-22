local actions = require("ops.actions")
local probes = require("ops.probes")
local default_adapter = require("ops.process")
local cjson = require("cjson.safe")

local M = {}

local fixed_commands = {
	nixos_version = {"/run/current-system/sw/bin/nixos-version"},
	df = {"df", "-P", "/", "/home"},
	zpool_summary = {"zpool", "status", "-x"},
	zpool_status = {"zpool", "status"},
	zpool_list = {"zpool", "list", "-H", "-o", "name,health,size,alloc,free,cap,frag"},
	zfs_datasets = {"zfs", "list", "-H", "-o", "name,compression,compressratio"},
	ollama_tags = {"curl", "--fail", "--silent", "--show-error", "--max-time", "3", "http://127.0.0.1:11434/api/tags"},
	network_hogs = {"/home/pmarreck/bin/nethogs", "-d", "1"},
	steam_shader = {"pgrep", "-af", "fossilize_replay|steam.*shader|shader.*precache"},
	journal_errors = {"journalctl", "-b", "-p", "err..alert", "--since", "-12 hours", "-n", "200", "--no-pager", "--output=short-iso"},
}

local codex_binary = "/home/pmarreck/.local/bin/codex"
local mechatron_control_binary = "/run/current-system/sw/bin/mechatron-prime-control"
local recent_ci_query = [[SELECT repository, commit_sha, status, failure_stage, failure_detail, started_at, finished_at FROM ci_runs ORDER BY finished_at DESC LIMIT 10;]]
local ci_history_query = [[SELECT repository, commit_sha, status, failure_stage, failure_detail, started_at, finished_at FROM ci_runs ORDER BY finished_at DESC LIMIT 100;]]

local function trim(text)
	return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function append(destination, values)
	for _, value in ipairs(values) do destination[#destination + 1] = value end
	return destination
end

--- Construct the privileged host adapter from an injected process boundary;
--- exact command vectors remain inspectable and deterministic in unit tests.
function M.new(adapter)
	adapter = adapter or default_adapter
	local system = {}

	local function timed(argv)
		local command = {"timeout", "5"}
		append(command, argv)
		return adapter.capture(command)
	end

	local function user_command(argv, needs_home)
		local command = {}
		if adapter.euid() == 0 then
			append(command, {"runuser", "-u", "pmarreck", "--"})
		end
		local environment = {"env"}
		if needs_home then environment[#environment + 1] = "HOME=/home/pmarreck" end
		environment[#environment + 1] = "XDG_RUNTIME_DIR=/run/user/1000"
		append(command, environment)
		append(command, argv)
		return command
	end

	--- Verify the managed daemon through Codex's control socket instead of
	--- trusting its PID record, which can survive a crash or reboot.
	function system.codex_remote_control()
		local output, ok = timed(user_command({codex_binary, "app-server", "daemon", "version"}, true))
		if not ok then return "inactive" end
		local document = trim(output)
		local status = cjson.decode(document)
		return status and status.status == "running" and "active" or "inactive"
	end

	function system.read(path)
		return adapter.read(path)
	end

	function system.now()
		return adapter.now()
	end

	function system.cpu_count()
		local cpuinfo = adapter.read("/proc/cpuinfo") or ""
		local count = 0
		for _ in cpuinfo:gmatch("\nprocessor%s*:") do count = count + 1 end
		if cpuinfo:match("^processor%s*:") then count = count + 1 end
		return math.max(1, count)
	end

	function system.service(scope, unit)
		local argv = {"systemctl", "is-active", unit}
		if scope == "user" then argv = user_command({"systemctl", "--user", "is-active", unit}) end
		local output = timed(argv)
		local state = trim(output)
		return state == "" and "unknown" or state
	end

	function system.timer(unit)
		local argv = user_command({"systemctl", "--user", "show", unit, "-p", "ActiveState", "-p", "SubState", "-p", "NextElapseUSecRealtime", "--no-pager"})
		local output = timed(argv)
		local properties = probes.parse_properties(output or "")
		return {
			state = properties.SubState or properties.ActiveState or "unknown",
			next_run = properties.NextElapseUSecRealtime ~= "" and properties.NextElapseUSecRealtime or "unknown",
		}
	end

	function system.run(name)
		local argv = fixed_commands[name]
		if name == "hogs" then
			argv = user_command({"bash", "-lc", "source /home/pmarreck/dotfiles/.aliases; hr; echo 'Memhogs:'; memhogs; hr; echo 'CPU hogs:'; cpuhogs; hr"})
		end
		if not argv then return nil end
		local output = timed(argv)
		return output
	end

	--- Project the ten newest terminal CI outcomes without exposing SQL, logs,
	--- output paths, or direct database access to tailnet clients.
	function system.recent_ci_runs()
		local output, ok = timed({"sqlite3", "-json", "/var/lib/mechatron-prime/results.sqlite3", recent_ci_query})
		if not ok then return {} end
		local decoded = cjson.decode(output)
		return type(decoded) == "table" and decoded or {}
	end

	--- Return a fixed, newest-first SQLite projection bounded independently of
	--- client input; private paths and delivery identifiers never enter SQL.
	function system.ci_history()
		local output, ok = timed({"sqlite3", "-json", "/var/lib/mechatron-prime/results.sqlite3", ci_history_query})
		if not ok then return {} end
		local decoded = cjson.decode(output)
		return type(decoded) == "table" and decoded or {}
	end

	function system.execute_action(action_id)
		local action = actions.resolve_id(action_id)
		if not action then return false, "action is not allowlisted" end
		if action.kind == "codex" then
			local command = {codex_binary}
			append(command, action.argv)
			local output, ok = timed(user_command(command, true))
			if not ok then return false, trim(output) ~= "" and trim(output) or "Codex action failed" end
			return true, trim(output)
		end
		if action.kind == "mechatron" then
			local command = {mechatron_control_binary}
			append(command, action.argv)
			local output, ok = timed(command)
			if not ok then return false, trim(output) ~= "" and trim(output) or "Mechatron action failed" end
			return true, trim(output)
		end
		local argv = {"systemctl", "--no-block", action.verb, action.unit}
		if action.scope == "user" then
			argv = user_command({"systemctl", "--user", "--no-block", action.verb, action.unit})
		end
		local output, ok = timed(argv)
		if not ok then return false, trim(output) ~= "" and trim(output) or "systemctl action failed" end
		return true
	end

	return system
end

return M
