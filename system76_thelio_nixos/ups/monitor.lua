-- Single invocation, serialized by a systemd oneshot timer. No agent needed.
local json = require('cjson')
local policy = dofile(assert(os.getenv('UPS_POLICY')))
local function read(path)
	local f = io.open(path, 'r')
	if not f then return nil end
	local value = f:read('*a'); f:close(); return value
end
local function atomic(path, value)
	local f = assert(io.open(path .. '.new', 'w'))
	assert(f:write(value)); assert(f:close())
	assert(os.rename(path .. '.new', path))
end
local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local now = assert(tonumber(assert(read('/proc/uptime')):match('^[%d.]+')))
local boot = assert(read('/proc/sys/kernel/random/boot_id')):gsub('%s+$', '')
local path = assert(os.getenv('STATE_DIRECTORY')) .. '/state.json'
local old = read(path)
local state = old and json.decode(old) or {}
local cmd = assert(os.getenv('UPS_QUERY'))
-- LuaJIT's Lua 5.1 pipe:close() can return true for a nonzero child exit.
-- Buffer stdout and append an explicit shell status; never trust partial data
-- from a failed/timed-out upsc query. cmd is a trusted, Nix-generated command.
local pipe = assert(io.popen('output=$(' .. cmd .. ' 2>/dev/null); rc=$?; '
 .. 'printf \'%s\\n__EVERAMP_EXIT__%s\\n\' "$output" "$rc"', 'r'))
local raw = pipe:read('*a')
pipe:close()
local status, code = raw:match('^(.*)\n__EVERAMP_EXIT__(%d+)\n$')
if code ~= '0' then status = nil end
local next_state, events = policy.step(state, status, now, boot)
-- last_at detects clock regression but doesn't require disk writes every poll.
local comparison = {}
for k,v in pairs(next_state) do if k ~= 'last_at' then comparison[k] = v end end
local changed = false
for k,v in pairs(comparison) do if state[k] ~= v then changed = true end end
for k in pairs(state) do if k ~= 'last_at' and comparison[k] == nil then changed = true end end
-- Persist the event outbox before invoking any effects. Restart retries it.
next_state.pending = state.boot == boot and state.pending or {}
next_state.pending = next_state.pending or {}
for _,event in ipairs(events) do next_state.pending[#next_state.pending+1] = event end
if changed or #events > 0 or not old then atomic(path, json.encode(next_state)) end
local armed = os.getenv('UPS_SHUTDOWN_ENABLED') == '1'
atomic(assert(os.getenv('RUNTIME_DIRECTORY')) .. '/status.json', json.encode({
	observed_at=os.date('!%Y-%m-%dT%H:%M:%SZ'), status=status or 'UNKNOWN',
	shutdown_enabled=armed, outage_elapsed_seconds=next_state.outage_since and now-next_state.outage_since,
	boot=boot,
}))
local notice_failed = false
while #next_state.pending > 0 do
	local event = next_state.pending[1]
	local sent = os.execute(quote(assert(os.getenv('UPS_NOTIFY'))) .. ' ' .. quote(event))
	if sent ~= 0 then notice_failed = true; break end
	table.remove(next_state.pending, 1)
	atomic(path, json.encode(next_state))
end
if next_state.shutdown_sent and next_state.outage_since and armed then
	-- Retry if a preceding poweroff request failed. Never invoke upsdrvctl -k,
	-- FSD, or a load-off command: enclosure/fan power must remain available.
	assert(os.execute(assert(os.getenv('UPS_POWEROFF'))) == 0, 'poweroff request failed')
end
if notice_failed then error('notification enqueue failed; outbox retained') end
