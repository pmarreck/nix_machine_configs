local M = {}

local status_text = {
	[200] = "OK",
	[303] = "See Other",
	[308] = "Permanent Redirect",
	[400] = "Bad Request",
	[403] = "Forbidden",
	[404] = "Not Found",
	[405] = "Method Not Allowed",
	[413] = "Content Too Large",
	[414] = "URI Too Long",
	[431] = "Request Header Fields Too Large",
	[500] = "Internal Server Error",
	[502] = "Bad Gateway",
	[503] = "Service Unavailable",
}

--- Parse one bounded HTTP/1 request with no pipelining or transfer coding;
--- this deliberately tiny protocol surface matches the internal console.
function M.parse(raw)
	local header_end = raw:find("\r\n\r\n", 1, true)
	if not header_end then return nil, #raw > 32768 and 431 or 400 end
	if header_end > 32768 then return nil, 431 end
	local header_block = raw:sub(1, header_end - 1)
	local body = raw:sub(header_end + 4)
	local request_line, remaining = header_block:match("^([^\r\n]+)\r\n?(.*)$")
	if not request_line then request_line, remaining = header_block, "" end
	local method, path, version = request_line:match("^([A-Z]+) (%S+) (HTTP/1%.[01])$")
	if not method then return nil, 400 end
	if #path > 4096 then return nil, 414 end
	if path:sub(1, 1) ~= "/" or path:find("[%z\r\n]") then return nil, 400 end

	local headers = {}
	if remaining ~= "" then
		for line in (remaining .. "\r\n"):gmatch("(.-)\r\n") do
			if line ~= "" then
				local name, value = line:match("^([!#$%%&'*+.^_`|~%w-]+):%s*(.-)%s*$")
				if not name then return nil, 400 end
				name = name:lower()
				if headers[name] ~= nil then return nil, 400 end
				headers[name] = value
			end
		end
	end
	if headers["transfer-encoding"] then return nil, 400 end
	local content_length = 0
	if headers["content-length"] then
		if not headers["content-length"]:match("^%d+$") then return nil, 400 end
		content_length = tonumber(headers["content-length"])
	end
	if content_length > 4096 then return nil, 413 end
	if #body ~= content_length then return nil, 400 end
	return {method = method, path = path, version = version, headers = headers, body = body}
end

--- Serialize a response with validated headers and an exact byte length so a
--- probe string can never create response splitting or ambiguous framing.
function M.encode(response)
	local reason = assert(status_text[response.status], "unsupported HTTP status")
	local body = response.body or ""
	local headers = {}
	for name, value in pairs(response.headers or {}) do
		assert(name:match("^[!#$%%&'*+.^_`|~%w-]+$"), "invalid response header name")
		assert(not tostring(value):find("[\r\n]"), "invalid response header value")
		headers[name] = tostring(value)
	end
	headers["Content-Length"] = tostring(#body)
	headers.Connection = "close"
	local names = {}
	for name in pairs(headers) do names[#names + 1] = name end
	table.sort(names)
	local lines = {"HTTP/1.1 " .. response.status .. " " .. reason}
	for _, name in ipairs(names) do lines[#lines + 1] = name .. ": " .. headers[name] end
	return table.concat(lines, "\r\n") .. "\r\n\r\n" .. body
end

return M
