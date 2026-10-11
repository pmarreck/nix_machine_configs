local M = {}

-- Read bytes under a hard cap, never an unbounded receive('*l'). A connection
-- timeout is supplied by the server; malformed framing reaches the HTTP parser.
function M.receive(client, now)
	now = now or require("socket").gettime
	local deadline = now() + 5
	local function receive(length)
		local remaining = deadline - now()
		if remaining <= 0 then return nil end
		client:settimeout(remaining)
		return client:receive(length)
	end
	local header = ""
	while not header:find("\r\n\r\n",1,true) do
		local byte = receive(1)
		if not byte then return nil end
		header = header .. byte
		if #header > 32768 then return header end
	end
	local length = 0
	for line in header:gmatch("[^\r\n]+") do
		local value = line:lower():match("^content%-length:%s*(%d+)%s*$")
		if value then length = tonumber(value) end
	end
	if length > 4096 then return header end
	if length == 0 then return header end
	local body = receive(length)
	return body and header .. body or nil
end

return M
