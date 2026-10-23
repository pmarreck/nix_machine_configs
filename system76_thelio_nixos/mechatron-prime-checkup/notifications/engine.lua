-- Effects are injected. save/export/stage return only after durable persistence.
local M = {}
local model=require("notifications.model")
function M.export(a,replay)
	assert(not replay or (replay>=1 and replay<=100 and replay==math.floor(replay)),"replay must be 1..100")
	local cursor=a.load("cursor")
	if not cursor then
		a.boundary("before-bootstrap")
		cursor={sequence=a.latest()}; a.save("cursor",cursor)
		a.boundary("after-bootstrap")
		if not replay then return end
	end
	assert(a.latest()>=cursor.sequence,"ledger regressed; inspect before resetting cursor")
	local after=replay and math.max(0,a.latest()-replay) or cursor.sequence
	for _,row in ipairs(a.results(after,replay or 200)) do
		local e=model.sanitize(row)
		if e then
			a.boundary("before-export"); a.export(a.identity(e),e); a.boundary("after-export")
		end
		if not replay then a.save("cursor",{sequence=row.sequence}); a.boundary("after-cursor") end
	end
end
local function deliver(a,e,role,route,reason)
	local id=a.identity(e).."-"..role
	local key="delivery-"..id
	local d=a.load(key) or {status="pending",attempts=0,event=e,role=role}
	if d.status=="delivered" or d.status=="uncertain" or d.status=="exhausted" then return d.status end
	if d.status=="sending" then
		local outcome=a.probe(d.route,id,d.bytes)
		d.status=outcome=="matching" and "delivered" or "uncertain"
		a.save(key,d); return d.status
	end
	if not route then d.status="unresolved"; a.save(key,d); return d.status end
	if d.next_attempt and a.now<d.next_attempt then return d.status end
	local ok,bytes=pcall(a.stage,id,e,role,reason)
	if not ok then
		d.attempts=d.attempts+1
		d.status=d.attempts>=5 and "exhausted" or "pending"
		d.next_attempt=a.now+60*2^(d.attempts-1)
		d.error="note staging failed"; a.save(key,d)
		return d.status
	end
	a.boundary("after-stage")
	d.bytes=bytes; d.route=route
	a.boundary("before-sending")
	d.status="sending"; d.attempts=d.attempts+1; a.save(key,d)
	a.boundary("after-sending")
	local outcome=a.publish(route,id,bytes)
	a.boundary("after-publish")
	if outcome=="published" or outcome=="matching" then
		a.boundary("before-delivered"); d.status="delivered"
	elseif outcome=="retry" then
		d.status=d.attempts>=5 and "exhausted" or "pending"; d.next_attempt=a.now+60*2^(d.attempts-1)
	else d.status="uncertain" end
	a.save(key,d); a.boundary("after-delivered")
	return d.status
end
function M.dispatch(a)
	for _,e in ipairs(a.list()) do
		local route,reason=a.resolve(e)
		local status=deliver(a,e,"project",route,"queued")
		local admin_status
		if e.classification~="project" or status=="unresolved" or status=="uncertain" or status=="exhausted" then
			admin_status=deliver(a,e,"admin",a.admin,reason or status)
		end
		a.complete(e,status,admin_status)
	end
end
return M
