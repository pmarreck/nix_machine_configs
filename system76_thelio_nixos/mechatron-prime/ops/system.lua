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
	network_hogs = {"/home/pmarreck/bin/nethogs", "-d", "1"},
	steam_shader = {"pgrep", "-af", "fossilize_replay|steam.*shader|shader.*precache"},
	journal_errors = {"journalctl", "-b", "-p", "err..alert", "--since", "-12 hours", "-n", "200", "--no-pager", "--output=short-iso"},
}

local codex_pid_path = "/home/pmarreck/.codex/app-server-daemon/app-server.pid"
local codex_binary = "/home/pmarreck/.local/bin/codex"

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

	--- Validate Codex's own numeric PID record against /proc so a stale record
	--- after reboot cannot masquerade as a running remote-control daemon.
	function system.codex_remote_control()
		local record = cjson.decode(adapter.read(codex_pid_path) or "")
		local pid = record and record.pid
		if type(pid) ~= "number" or pid < 1 or pid % 1 ~= 0 then return "inactive" end
		local command_line = adapter.read("/proc/" .. pid .. "/cmdline")
		if not command_line or not command_line:find("codex", 1, true) or not command_line:find("app-server", 1, true) then
			return "inactive"
		end
		return "active"
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

	function system.execute_action(action_id)
		local action = actions.resolve_id(action_id)
		if not action then return false, "action is not allowlisted" end
		if action.kind == "codex-remote-control" then
			local output, ok = timed(user_command({codex_binary, "remote-control", action.verb, "--json"}, true))
			if not ok then return false, trim(output) ~= "" and trim(output) or "Codex remote-control action failed" end
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
