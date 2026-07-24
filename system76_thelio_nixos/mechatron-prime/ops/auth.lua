local M = {}

-- The listener is loopback-only and its Tailscale Serve route is private.  That
-- route is deliberately the sole authorization boundary for Peter's personal
-- operations console: identity/origin headers are optional telemetry, not an
-- additional capability gate that can strand a legitimate tailnet client.
function M.authorize(_headers)
	return true
end

return M
