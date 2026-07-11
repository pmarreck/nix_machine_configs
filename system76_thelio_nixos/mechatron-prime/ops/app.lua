local http = require("ops.http")
local router = require("ops.router")

local M = {}

local function error_response(status, message)
	return {
		status = status,
		headers = {
			["Content-Type"] = "text/plain; charset=utf-8",
			["Cache-Control"] = "no-store",
			["X-Content-Type-Options"] = "nosniff",
		},
		body = message .. "\n",
	}
end

--- Compose parsing, cached snapshot collection, exact routing, and response
--- framing behind one pure string boundary suitable for socket and unit tests.
function M.new(provider, clock, cache_seconds)
	clock = clock or os.time
	cache_seconds = cache_seconds or 5
	local cached_model = nil
	local cached_at = nil
	local app = {}

	local function model()
		local now = clock()
		if not cached_model or not cached_at or now - cached_at >= cache_seconds then
			cached_model = provider.model()
			cached_at = now
		end
		return cached_model
	end

	local function execute_action(action_id)
		local ok, action_error = provider.execute_action(action_id)
		if ok then cached_model, cached_at = nil, nil end
		return ok, action_error
	end

	function app.handle(raw_request)
		local request, parse_status = http.parse(raw_request)
		if not request then return http.encode(error_response(parse_status, "invalid request")) end
		local ok, response = pcall(router.dispatch, request, {model = model, execute_action = execute_action})
		if not ok then response = error_response(500, "operations probe failed: " .. tostring(response)) end
		return http.encode(response)
	end

	return app
end

return M
