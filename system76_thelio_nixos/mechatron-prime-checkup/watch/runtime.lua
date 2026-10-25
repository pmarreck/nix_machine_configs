local json=require('cjson.safe')
local fs=require('notifications.fs')
local command=require('notifications.adapters').command
local collect=require('watch.collect')
local model=require('watch.model')
local M={}
function M.collect(config)
	local runtime=os.getenv('XDG_RUNTIME_DIR')
	if not runtime then runtime='/run/user/'..assert(command({'id','-u'}):match('^%d+')) end
	return collect.run({now=os.date('!%Y-%m-%dT%H:%M:%SZ'),runtime=runtime,command=command,read=function(path)
		local f=io.open(path,'r'); if not f then return nil end
		local bytes=f:read(1048576); f:close(); return bytes
	end},config)
end
function M.new(config)
	assert(type(config.state)=='string' and config.state:sub(1,1)=='/','absolute state directory required')
	fs.mkdir(config.state,448)
	local p={now=os.time()}
	local sign,hours,minutes=os.date('%z',p.now):match('([+-])(%d%d)(%d%d)')
	p.utc_offset=hours and (tonumber(hours)*3600+tonumber(minutes)*60)*(sign=='-' and -1 or 1) or 0
	p.unlock=fs.lock(config.state..'/.lock',true); assert(p.unlock,'checkup state lock unavailable')
	local path=config.state..'/latest.json'
	function p.load() local bytes=fs.read(path,131072); return bytes and assert(json.decode(bytes),'invalid checkup state') end
	function p.save(state) fs.atomic(path,assert(json.encode(state))..'\n',384) end
	function p.collect() return M.collect(config) end
	function p.publish(id,snapshot)
		assert(config.inbox and config.project,'private recipient routing required')
		local stage=config.state..'/staging'; fs.mkdir(stage,448)
		local names=fs.files(stage,'.frontmatter.md'); assert(#names<=1,'ambiguous checkup staging')
		local bytes,name
		if names[1] then
			name=names[1]; bytes=fs.read(stage..'/'..name,131072)
			local header=json.decode(bytes:match('^%-%-%-json\n(.-)\n%-%-%-') or '')
			if not header or header.subject~='Host checkup '..id then fs.unlink(stage..'/'..name); bytes=nil end
		end
		if not bytes then
			local body=config.state..'/body.txt'
			fs.atomic(body,'Three-hour host snapshot. Expected OCR training may saturate CPU/GPU. Normal acknowledgement: Looks good.\n\n'..assert(json.encode(snapshot))..'\n',384)
			command({'timeout','15s',os.getenv('LLMSEND_WRITE_NOTE') or 'llmsend-write-note','--inbox',stage,
				'--sender','mechatron-checkup','--recipient','mechatron-prime','--subject','Host checkup '..id,
				'--description','Review host resources and storage; a short acknowledgement is enough if normal.',
				'--type','status','--response-expected','true','--priority',snapshot.health.status=='critical' and 'high' or 'normal','--tag','host-checkup'},body)
			names=fs.files(stage,'.frontmatter.md'); assert(#names==1,'checkup writer did not publish one note')
			name=names[1]; bytes=fs.read(stage..'/'..name,131072)
		end
		local route=fs.route(config.inbox)
		local result=fs.publish(route,name:gsub('%.frontmatter%.md$',''),bytes)
		assert(result=='published' or result=='matching','checkup inbox publication '..result)
		return config.inbox..'/'..name
	end
	function p.deliver(note,id)
		if not fs.read(note,131072) then return {status='note-gone',reason='note removed; not proof of acknowledgement'} end
		local native_dir=os.getenv('LLMSEND_NATIVE_DIR')
		if not native_dir then return {status='deferred',reason='native-adapter-unavailable'} end
		package.path=native_dir..'/?.lua;'..package.path
		local rpc=require('unix_rpc'); local native=require('native_delivery'); local store=require('reminder_store')
		local ok,socket=pcall(store.canonical,config.socket)
		if not ok then return {status='deferred',reason='native-socket-unavailable'} end
		local connection,reason=rpc.connect(socket,8)
		if not connection then return {status='deferred',reason=reason} end
		local worked,result=pcall(function()
			return native.new(connection,{thread=config.thread,project=config.project}).deliver(model.review_prompt(note),id)
		end)
		connection.close()
		return worked and result or {status='unconfirmed',reason='native-delivery-error'}
	end
	function p.notify(id,snapshot)
		if type(config.mail)~='table' or #config.mail==0 then return false end
		local argv={'timeout','20s'}; for _,v in ipairs(config.mail) do argv[#argv+1]=v end
		argv[#argv+1]='--subject'; argv[#argv+1]='Host checkup: '..snapshot.health.status
		argv[#argv+1]='--body'; argv[#argv+1]='Host checkup '..id..' needs attention.\n'..assert(json.encode(snapshot.health))..'\nInspect mechatron-checkup --status for the private snapshot. No jobs were stopped.'
		argv[#argv+1]='--yes'
		return pcall(command,argv)
	end
	return p
end
return M
