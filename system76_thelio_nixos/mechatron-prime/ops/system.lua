local actions = require("ops.actions")
local live = require("ops.live")
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
	ollama_ps = {"curl", "--fail", "--silent", "--show-error", "--max-time", "3", "http://127.0.0.1:11434/api/ps"},
	network_hogs = {"/home/pmarreck/bin/nethogs", "-d", "1"},
	steam_shader = {"pgrep", "-af", "fossilize_replay|steam.*shader|shader.*precache"},
	journal_errors = {"journalctl", "-b", "-p", "err..alert", "--since", "-12 hours", "-n", "200", "--no-pager", "--output=short-iso"},
}

local codex_binary = "/home/pmarreck/.local/bin/codex"
local mechatron_control_binary = "/run/current-system/sw/bin/mechatron-prime-control"
local clocksound_timer = "clocksound.timer"
local recent_ci_query = [[SELECT repository, commit_sha, status, failure_stage, failure_detail, started_at, finished_at FROM ci_runs ORDER BY finished_at DESC LIMIT 10;]]
-- The history projection is bounded only as a runaway guard, not as a display
-- window. It used to stop at 100 rows, which silently hid most of the ledger
-- from filtered lookups; filtering now happens over everything the guard admits,
-- and the query asks for one row PAST the bound so truncation is detectable
-- rather than assumed.
local ci_history_bound = 5000
local ci_history_query = string.format([[SELECT repository, commit_sha, status, failure_stage, failure_detail, started_at, finished_at FROM ci_runs ORDER BY finished_at DESC LIMIT %d;]], ci_history_bound + 1)

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

	--- Read a managed system unit's load and run state.  `is-active` cannot
	--- answer the question the console needs, because an operator's mask and a
	--- service that died both read as not-active; only LoadState separates them.
	function system.unit(scope, unit)
		local argv = {"systemctl", "show", unit, "-p", "LoadState", "-p", "ActiveState", "-p", "SubState", "--no-pager"}
		if scope == "user" then argv = user_command({"systemctl", "--user", "show", unit, "-p", "LoadState", "-p", "ActiveState", "-p", "SubState", "--no-pager"}) end
		local output = timed(argv)
		local properties = probes.parse_properties(output or "")
		return {
			load_state = properties.LoadState or "unknown",
			active_state = properties.ActiveState or "unknown",
			sub_state = properties.SubState or "unknown",
		}
	end

	--- Read a user timer's arming state.  LoadState is requested alongside the
	--- run state because a masked unit reports ActiveState=failed: without it a
	--- deliberate mute is indistinguishable from a genuine timer fault.
	function system.timer(unit)
		local argv = user_command({"systemctl", "--user", "show", unit, "-p", "LoadState", "-p", "ActiveState", "-p", "SubState", "-p", "NextElapseUSecRealtime", "--no-pager"})
		local output = timed(argv)
		local properties = probes.parse_properties(output or "")
		return {
			state = properties.SubState or properties.ActiveState or "unknown",
			load_state = properties.LoadState or "unknown",
			active_state = properties.ActiveState or "unknown",
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

	--- Read one fixed, newest-first ledger projection.  Returns the decoded rows,
	--- or nil and a reason -- NEVER an empty list on failure, because an empty
	--- list is indistinguishable from a truthful empty ledger and that ambiguity
	--- is how a failed read came to look like "no such run".
	local function read_ledger(query)
		local output, ok = timed({"sqlite3", "-json", "/var/lib/mechatron-prime/results.sqlite3", query})
		if not ok then
			return nil, trim(output) ~= "" and trim(output) or "the result ledger could not be read"
		end
		-- sqlite3 prints nothing for a zero-row result; that IS the empty ledger.
		if trim(output) == "" then return {} end
		local decoded = cjson.decode(output)
		if type(decoded) ~= "table" then return nil, "the result ledger returned an unreadable projection" end
		return decoded
	end

	--- Project the ten newest terminal CI outcomes without exposing SQL, logs,
	--- output paths, or direct database access to tailnet clients.  Returns nil
	--- when the ledger cannot be read, so the page can say so.
	function system.recent_ci_runs()
		return read_ledger(recent_ci_query)
	end

	--- Return the newest-first ledger projection bounded independently of client
	--- input; private paths and delivery identifiers never enter SQL.  Filtering
	--- happens above this, over the rows returned here.
	function system.ci_history()
		local rows, reason = read_ledger(ci_history_query)
		if not rows then return nil, reason end
		local truncated = #rows > ci_history_bound
		while #rows > ci_history_bound do rows[#rows] = nil end
		return {runs = rows, truncated = truncated, generated_at = system.now()}
	end

	--- Read only the small CI state projection.  This avoids running host-health
	--- probes (including resource snapshots) when a project agent merely wants
	--- to see its queue position.
	function system.ci_queue()
		return live.collect_mechatron(system)
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
		--- Chime controls run a fixed SEQUENCE and abort on the first failure.
		--- Continuing past a failed unmask would start a timer that is still
		--- masked, reporting success while the chime stayed silent.
		if action.kind == "clocksound" then
			for _, step in ipairs(action.steps) do
				local command = {"systemctl", "--user"}
				append(command, step)
				command[#command + 1] = clocksound_timer
				local output, ok = timed(user_command(command))
				if not ok then return false, trim(output) ~= "" and trim(output) or "chime action failed" end
			end
			return true
		end
		--- System-unit controls run the same abort-on-first-failure sequence as
		--- the chime.  Starting a service whose mask is still in place would
		--- report success while it stayed down.
		if action.kind == "system-unit" then
			for _, step in ipairs(action.steps) do
				local command = {"systemctl"}
				append(command, step)
				command[#command + 1] = action.unit
				local output, ok = timed(command)
				if not ok then return false, trim(output) ~= "" and trim(output) or "service action failed" end
			end
			return true
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
