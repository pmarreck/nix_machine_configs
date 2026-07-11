local ffi = require("ffi")

ffi.cdef[[
unsigned int geteuid(void);
]]

local M = {}

local function shell_quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

--- Capture a fixed argv vector through the host shell with POSIX single-quote
--- escaping; callers never pass request-derived values into this boundary.
function M.capture(argv)
	local quoted = {}
	for index, value in ipairs(argv) do quoted[index] = shell_quote(value) end
	local handle, open_error = io.popen(table.concat(quoted, " ") .. " 2>&1", "r")
	if not handle then return nil, false, open_error end
	local output = handle:read("*a")
	local ok, reason, code = handle:close()
	return output, ok == true, code or reason
end

function M.read(path)
	local handle = io.open(path, "rb")
	if not handle then return nil end
	local content = handle:read("*a")
	handle:close()
	return content
end

function M.now()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

function M.euid()
	return tonumber(ffi.C.geteuid())
end

return M
