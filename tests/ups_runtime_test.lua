-- Execute the production adapter against injected OS/file/process boundaries.
-- No real notices, services, device writes, or shutdown commands are possible.
local json = require('cjson')
local script, policy = arg[1], arg[2]
local real_open, real_popen = io.open, io.popen
local real_getenv, real_execute, real_rename = os.getenv, os.execute, os.rename
local files, calls, now, boot, status, query_ok, notify_ok, armed
local real_query
local function run(seed)
 files, calls = seed or {}, {}
 files['/proc/uptime'] = tostring(now) .. ' 0'
 files['/proc/sys/kernel/random/boot_id'] = boot
 local env = {UPS_POLICY=policy, STATE_DIRECTORY='/state', RUNTIME_DIRECTORY='/run',
  UPS_QUERY=real_query or 'QUERY', UPS_NOTIFY='NOTICE', UPS_POWEROFF='POWEROFF', UPS_SHUTDOWN_ENABLED=armed}
 os.getenv = function(k) return env[k] end
 io.open = function(path, mode)
  if path == policy then return real_open(path, mode) end
  if mode == 'r' and files[path] == nil then return nil end
  return {read=function() return files[path] end,
   write=function(_, s) files[path]=s; return true end, close=function() return true end}
 end
 io.popen = function(cmd)
  if real_query then return real_popen(cmd, 'r') end
  return {read=function() return status .. '\n__EVERAMP_EXIT__' .. (query_ok and '0' or '1') .. '\n' end,
   close=function() return true end}
 end
 os.rename = function(a,b) files[b]=files[a]; files[a]=nil; return true end
 os.execute = function(cmd)
  calls[#calls+1]=cmd
  if cmd:find('NOTICE',1,true) and not notify_ok then return 1 end
  return 0
 end
 local ok, err = pcall(dofile, script)
 io.open, io.popen = real_open, real_popen
 os.getenv, os.execute, os.rename = real_getenv, real_execute, real_rename
 return ok, err
end
local function has(needle)
 for _, c in ipairs(calls) do if c:find(needle,1,true) then return true end end
 return false
end
now,boot,status,query_ok,notify_ok,armed=100,'a','OB',true,true,'0'
assert(run())
local state = files
now=701
assert(run(state))
assert(has('shutdown') and not has('POWEROFF'), 'observation mode never powers off')
armed='1'; notify_ok=false
local seed=json.encode({boot='a',last_at=100,outage_since=100})
run({['/state/state.json']=seed})
assert(has('POWEROFF'), 'failed notice must not block armed shutdown')
notify_ok=true
status='OL'
assert(run({['/state/state.json']=seed}))
assert(not has('POWEROFF'), 'restored mains cancels poweroff at deadline')
status='OB';query_ok=nil
assert(run())
assert(not has('POWEROFF'), 'failed query cannot fabricate an outage from partial stdout')
assert(json.decode(files['/state/state.json']).outage_since == nil)
query_ok=true;status='OL';boot='b';now=1
seed=json.encode({boot='a',last_at=701,outage_since=100,pending={'shutdown'}})
assert(run({['/state/state.json']=seed}))
assert(not has('shutdown'), 'new boot must not replay stale shutdown notice')
assert(not has('POWEROFF'))
print('5 UPS runtime boundary scenarios passed')
-- External oracle: real POSIX shell exit codes, including partial stdout.
now,boot,armed,notify_ok=701,'a','1',true
for _, query in ipairs({'printf OB; exit 1', 'printf OB; exit 0'}) do
 real_query=query
 assert(run())
 local outage = json.decode(files['/state/state.json']).outage_since
 assert((outage ~= nil) == (query == 'printf OB; exit 0'), 'real query exit status controls acceptance')
end
print('2 real subprocess exit-status scenarios passed')
