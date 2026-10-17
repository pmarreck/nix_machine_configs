local json = require("cjson.safe")
local http = require("ops.http")
local model = require("provision.model")
local M = {}

function M.new(adapter)
	local state = {owner="pmarreck",requests_total=0,ready_at=adapter.now()}
	local function response(status, document)
		return http.encode({status=status,headers={
			["Content-Type"]="application/json",["Cache-Control"]="no-store",
		},body=assert(json.encode(document)) .. "\n"})
	end
	local function save()
		local ok, result = pcall(adapter.save, state)
		return ok and result ~= false
	end
	return {handle=function(raw)
		local r, code = http.parse(raw)
		if not r then return response(code,{error="invalid request"}) end
		if next(r.query) then return response(400,{error="query fields forbidden"}) end
		if r.method == "GET" and r.path == "/status.json" and r.body == "" then return response(200,state) end
		if r.path ~= "/provision" then return response(404,{error="unknown route"}) end
		if r.method ~= "POST" then return response(405,{error="POST required"}) end
		local request = model.validate(json.decode(r.body))
		if not request then return response(400,{error="invalid owned repository request"}) end
		state.requests_total = state.requests_total + 1
		state.last = {repository=request.repository,dry_run=request.dry_run,result="running",started_at=adapter.now()}
		if not save() then
			state.last.result = "failure"
			state.last.finished_at = adapter.now()
			return response(503,{error="status storage unavailable; no provisioning attempted"})
		end
		local called, succeeded = pcall(adapter.ensure,request.repository,request.dry_run)
		local ok = called and succeeded == true
		state.last.result = ok and "success" or "failure"
		state.last.finished_at = adapter.now()
		if not save() then return response(503,{error="status storage unavailable; inspect hook before retry"}) end
		if not ok then return response(502,{error="GitHub provisioning failed or timed out; retry performs a fresh preflight",last=state.last}) end
		return response(200,{ok=true,last=state.last})
	end}
end

return M
