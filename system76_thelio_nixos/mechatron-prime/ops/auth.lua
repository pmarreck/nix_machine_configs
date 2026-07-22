local M = {}

--- Authorize fixed mutations from Tailscale Serve's spoof-resistant user
--- identity while rejecting browser requests from foreign or opaque origins.
function M.authorize(headers, expected_login, expected_origin)
	headers = headers or {}
	if expected_login == "" or headers["tailscale-user-login"] ~= expected_login then
		return false
	end
	local origin = headers.origin
	if origin ~= nil and origin ~= expected_origin then return false end
	return true
end

return M
