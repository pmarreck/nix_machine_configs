local socket = require("socket")
local app_factory = require("ops.app")
local live = require("ops.live")
local auth = require("ops.auth")
local system = require("ops.system").new()

local address = os.getenv("MECHATRON_OPS_ADDRESS") or "127.0.0.1"
local port = tonumber(os.getenv("MECHATRON_OPS_PORT") or "9002")

local provider = {
	model = function() return live.collect(system) end,
	ci_history = function() return system.ci_history(), system.now() end,
	execute_action = system.execute_action,
	authorize_action = function(request)
		return auth.authorize(request.headers)
	end,
}
local app = app_factory.new(provider, socket.gettime, 5)

local listener, bind_error = socket.bind(address, port)
if not listener then error("could not bind operations server: " .. tostring(bind_error)) end
listener:settimeout(nil)
io.stderr:write(string.format("Mechatron Prime operations listening on %s:%d\n", address, port))

local function receive_request(client)
	client:settimeout(5)
	local first, first_error = client:receive("*l")
	if not first then return nil, first_error end
	local lines = {first}
	local header_bytes = #first + 2
	local content_length = 0
	while true do
		local line, line_error = client:receive("*l")
		if not line then return nil, line_error end
		header_bytes = header_bytes + #line + 2
		if header_bytes > 32768 then return string.rep("x", 32769) end
		if line == "" then break end
		lines[#lines + 1] = line
		local value = line:match("^[Cc][Oo][Nn][Tt][Ee][Nn][Tt]%-[Ll][Ee][Nn][Gg][Tt][Hh]:%s*(%d+)%s*$")
		if value then content_length = tonumber(value) end
	end
	local body = ""
	if content_length > 0 and content_length <= 4096 then
		local received, body_error, partial = client:receive(content_length)
		body = received or partial or ""
		if body_error and body == "" then return nil, body_error end
	end
	return table.concat(lines, "\r\n") .. "\r\n\r\n" .. body
end

while true do
	local client = listener:accept()
	if client then
		local raw_request = receive_request(client)
		if raw_request then
			local ok, response = pcall(app.handle, raw_request)
			if ok then
				client:send(response)
			else
				io.stderr:write("operations request failed: " .. tostring(response) .. "\n")
			end
		end
		client:close()
	end
end
