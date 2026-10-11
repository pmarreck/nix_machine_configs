local listener_adapter = require("provision.listener")
local json = require("cjson.safe")
local app_factory = require("provision.app")
local transport = require("provision.transport")
local runner = assert(os.getenv("MECHATRON_PROVISION_RUNNER"),"runner required")
local status_path = os.getenv("MECHATRON_PROVISION_STATUS") or "/run/mechatron-prime-provision/status.json"
local function quote(s) return "'" .. s:gsub("'","'\\''") .. "'" end
local app = app_factory.new({
	now=function() return os.date("!%Y-%m-%dT%H:%M:%SZ") end,
	save=function(state)
		local f = assert(io.open(status_path .. ".tmp","w"))
		assert(f:write(assert(json.encode(state)) .. "\n")); assert(f:close())
		assert(os.rename(status_path .. ".tmp",status_path))
	end,
	ensure=function(repository,dry_run)
		local command = "timeout --kill-after=5 90 " .. quote(runner) .. " " .. quote(repository) .. " " .. (dry_run and "dry" or "live") .. " 2>/dev/null"
		local pipe = assert(io.popen(command,"r"))
		local result = pipe:read(32)
		pipe:close()
		return result == "success\n"
	end,
})
-- NixOS owns the listening socket and its operator-only filesystem permissions.
-- setfd adopts systemd's already-listening descriptor without rebinding it.
assert(os.getenv("LISTEN_FDS") == "1", "one systemd socket required")
local listener = listener_adapter.adopt(3)
while true do
	local client = listener:accept()
	if client then
		client:settimeout(5)
		local raw = transport.receive(client)
		if raw then
			local ok, response = pcall(app.handle,raw)
			if ok then client:send(response) end
		end
		client:close()
	end
end
