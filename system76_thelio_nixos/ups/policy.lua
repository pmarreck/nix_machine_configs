-- Pure outage policy: caller supplies monotonic seconds and boot identity.
-- Runtime estimates and USB port numbers deliberately do not enter decisions.
local M = {}
function M.step(previous, status, now, boot)
	assert(type(now) == 'number' and now >= 0 and now < math.huge)
	assert(type(boot) == 'string' and #boot > 0)
	local s, events = {}, {}
	if previous.boot == boot then
		for k, v in pairs(previous) do s[k] = v end
		assert(not s.last_at or now >= s.last_at, 'monotonic clock regressed')
	end
	s.boot, s.last_at = boot, now
	local tokens = {}
	for t in tostring(status or ''):gmatch('%S+') do tokens[t] = true end
	local valid = not tokens.CAL and (tokens.OL ~= tokens.OB)
	local mode = valid and (tokens.OL and 'online' or 'battery') or 'unknown'
	local function emit(e) events[#events + 1] = e end
	if mode == 'unknown' then
		if not s.lost then emit('communication-lost') end
		s.lost = true
	else
		if s.lost then emit('communication-restored') end
		s.lost = nil
		if mode == 'online' then
			if s.outage_since then emit('online') end
			s.outage_since, s.warning_sent, s.shutdown_sent = nil, nil, nil
		elseif not s.outage_since then
			s.outage_since = now
			emit('on-battery')
		end
	end
	if s.outage_since then
		local elapsed = now - s.outage_since
		if elapsed >= 600 and not s.shutdown_sent then
			s.shutdown_sent = true
			emit('shutdown')
		elseif elapsed >= 300 and not s.warning_sent and not s.shutdown_sent then
			s.warning_sent = true
			emit('five-minutes')
		end
	end
	return s, events
end
return M
