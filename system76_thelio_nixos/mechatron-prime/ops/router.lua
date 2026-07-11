local cjson = require("cjson.safe")
local actions = require("ops.actions")
local render = require("ops.render")

local M = {}

local function headers(content_type)
	return {
		["Content-Type"] = content_type,
		["Cache-Control"] = "no-store",
		["X-Content-Type-Options"] = "nosniff",
		["Referrer-Policy"] = "no-referrer",
	}
end

local function text_response(status, body)
	return {
		status = status,
		headers = headers("text/plain; charset=utf-8"),
		body = body,
	}
end

local function json_response(status, document)
	local encoded, encode_error = cjson.encode(document)
	if not encoded then
		return text_response(500, "could not encode response: " .. tostring(encode_error) .. "\n")
	end
	return {
		status = status,
		headers = headers("application/json; charset=utf-8"),
		body = encoded .. "\n",
	}
end

--- Dispatch an already-parsed request through a closed route table; adapters
--- provide immutable snapshots and execute only resolved action identities.
function M.dispatch(request, dependencies)
	if request.path == "/ops" then
		return {
			status = 308,
			headers = {Location = "/ops/", ["Cache-Control"] = "no-store"},
			body = "",
		}
	end

	if request.path == "/ops/" then
		if request.method ~= "GET" then
			local response = text_response(405, "method not allowed\n")
			response.headers.Allow = "GET"
			return response
		end
		local response = {
			status = 200,
			headers = headers("text/html; charset=utf-8"),
			body = render.page(dependencies.model()),
		}
		response.headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'"
		return response
	end

	if request.path == "/ops/health.json" then
		if request.method ~= "GET" then
			local response = text_response(405, "method not allowed\n")
			response.headers.Allow = "GET"
			return response
		end
		local model = dependencies.model()
		return {
			status = model.health.status == "healthy" and 200 or 503,
			headers = headers("application/json; charset=utf-8"),
			body = render.health_json(model),
		}
	end

	local action = actions.resolve(request.path)
	if action then
		if request.method ~= "POST" then
			local response = text_response(405, "method not allowed\n")
			response.headers.Allow = "POST"
			return response
		end
		local ok, action_error = dependencies.execute_action(action.id)
		if not ok then
			return json_response(502, {status = "error", error = action_error or "action failed"})
		end
		return {
			status = 303,
			headers = {Location = "/ops/", ["Cache-Control"] = "no-store"},
			body = "",
		}
	end

	return text_response(404, "not found\n")
end

return M
