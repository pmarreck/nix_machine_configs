-- One sample per three-hour slot. External effects have durable checkpoints.
local model=require('watch.model')
local M={}
function M.run(p,delivery_only)
	local state=p.load()
	local slot=math.floor((p.now+(p.utc_offset or 0))/10800)
	if not delivery_only and (not state or slot>state.slot) then
		local s=p.collect(); s.health=model.evaluate(s)
		state={slot=slot,id='host-checkup-'..slot,snapshot=s,native={status='pending'},alert=state and state.alert}
		p.save(state)
	end
	if not state then return {status='empty'} end
	if not state.note then state.note=p.publish(state.id,state.snapshot); p.save(state) end
	if state.native.status=='pending' or state.native.status=='deferred' then
		-- Uncertain sends are not immediately replayed, including after a crash.
		state.native={status='unconfirmed'}; p.save(state)
		state.native=p.deliver(state.note,state.id); p.save(state)
	end
	local h=state.snapshot.health
	local retry=state.alert and state.alert.status=='failed' and (state.alert.attempts or 1)<3 and p.now-state.alert.at>=300
	if h.status~='healthy' and (not state.alert or state.alert.key~=h.key or p.now-state.alert.at>=86400 or retry) then
		local attempts=retry and state.alert.key==h.key and (state.alert.attempts or 1)+1 or 1
		state.alert={key=h.key,at=p.now,status='unconfirmed',attempts=attempts}; p.save(state)
		state.alert.status=p.notify(state.id,state.snapshot) and 'sent' or 'failed'; p.save(state)
	elseif h.status=='healthy' and state.alert then state.alert=nil; p.save(state) end
	return state
end
return M
