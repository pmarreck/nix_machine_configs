local unix = require("socket.unix")
local M = {}
function M.adopt(fd)
	local listener = assert(unix.stream())
	listener:setfd(fd)
	-- listen also sets LuaSocket's server class for the inherited descriptor.
	assert(listener:listen(8))
	listener:settimeout(nil)
	return listener
end
return M
