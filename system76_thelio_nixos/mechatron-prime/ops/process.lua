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
--- LuaJIT's default (Lua 5.1) mode reports a popen close as success whatever
--- the exit status, so the shell appends the status after the output and it is
--- split off here: ok only for 0, code 128 + N for a command killed by signal N.
function M.capture(argv)
	local quoted = {}
	for index, value in ipairs(argv) do quoted[index] = shell_quote(value) end
	local handle, open_error = io.popen(table.concat(quoted, " ") .. ' 2>&1; printf "\\n%d" "$?"', "r")
	if not handle then return nil, false, open_error end
	local raw = handle:read("*a")
	handle:close()
	local output, status = raw:match("^(.*)\n(%d+)$")
	if not output then return raw, false, "no exit status from the shell" end
	local code = tonumber(status)
	return output, code == 0, code
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
