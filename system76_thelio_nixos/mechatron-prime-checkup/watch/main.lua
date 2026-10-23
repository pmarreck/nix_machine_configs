local root=arg[0]:match('^(.*)/watch/') or '.'
package.path=root..'/?.lua;'..package.path
local json=require('cjson.safe')
local mode='snapshot'
local config_path=(os.getenv('HOME') or '')..'/.config/mechatron-checkup/config.json'
local i=1
while i<=#arg do
	local value=arg[i]
	if value=='--help' or value=='-h' then
		print('mechatron-checkup: bounded Linux host check and three-hour agent review')
		print('Usage: mechatron-checkup [--json|--run|--deliver|--status] [--config FILE]')
		print('Default: read-only JSON snapshot. --run: durable sample, alert and native review. --deliver: retry a deferred review without sampling. --status: last saved outcome.')
		return
	elseif value=='--about' then print('mechatron-checkup 0.1.0: private host resource and ZFS check (Linux/'..require('jit').arch..')'); return
	elseif value=='--config' and arg[i+1] then i=i+1; config_path=arg[i]
	elseif value=='--json' then
	elseif value=='--run' then mode='run'
	elseif value=='--deliver' then mode='deliver'
	elseif value=='--status' then mode='status'
	else io.stderr:write('Invalid checkup option; use --help.\n'); os.exit(2) end
	i=i+1
end
local port
local ok,result=pcall(function()
	local fs=require('notifications.fs')
	local config
	if config_path=='-' or config_path=='@stdin' then config=assert(json.decode(io.read('*a')))
	else
		local f=io.open(config_path,'r')
		if f then f:close(); config=assert(json.decode(fs.private_config(config_path)))
		elseif mode~='snapshot' then error('private checkup configuration is missing') end
	end
	config=config or {}
	local runtime=require('watch.runtime')
	if mode=='snapshot' then
		local sample=runtime.collect(config); sample.health=require('watch.model').evaluate(sample); return sample
	end
	port=runtime.new(config)
	if mode=='status' then return port.load() or {status='empty'} end
	return require('watch.engine').run(port,mode=='deliver')
end)
if port and port.unlock then port.unlock() end
if not ok then io.stderr:write('Checkup failed: '..tostring(result)..'\n'); os.exit(1) end
print(assert(json.encode(result)))
