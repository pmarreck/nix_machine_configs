-- Bounded, read-only probes through injected process and file adapters.
local probes=require('ops.probes')
local queues=require('watch.queues')
local M={}
function M.notable(line)
	for _,pattern in ipairs({'Out of memory:','oom%-kill:','NVRM: Xid','I/O error','blk_update_request','nvme.-timeout','nvme.-reset controller','ZFS.-FAULT'}) do
		if line:find(pattern) then return true end
	end
	return false
end
local function cpu(text)
	local values={}; for n in (text:match('^cpu%s+([^\n]+)') or ''):gmatch('%d+') do values[#values+1]=tonumber(n) end
	local total=0; for i=1,math.min(8,#values) do total=total+values[i] end
	local count=0; for _ in text:gmatch('\ncpu%d+%s') do count=count+1 end
	return {total=total,idle=(values[4] or 0)+(values[5] or 0),count=math.max(1,count)}
end
function M.run(p,config)
	config=config or {}
	local s={at=p.now,probe_errors={},memory={},disks={},pools={},gpus={},kernel_errors={},pressure={}}
	local function read(path) return p.read(path) or '' end
	local function command(argv)
		local args={'timeout','8s'}; for _,v in ipairs(argv) do args[#args+1]=v end
		local ok,value=pcall(p.command,args)
		if not ok then s.probe_errors[#s.probe_errors+1]=argv[1]..' probe failed'; return '' end
		return value
	end
	local start=cpu(read('/proc/stat'))
	local ok,memory=pcall(probes.parse_meminfo,read('/proc/meminfo'))
	if ok then s.memory=memory end
	local mem=read('/proc/meminfo'); local swap_total=tonumber(mem:match('SwapTotal:%s*(%d+)'))
	local swap_free=tonumber(mem:match('SwapFree:%s*(%d+)'))
	s.memory.swap_used_kib=swap_total and swap_free and swap_total-swap_free
	s.uptime_seconds=tonumber(read('/proc/uptime'):match('^[%d.]+'))
	s.boot_id=read('/proc/sys/kernel/random/boot_id'):gsub('%s+$','')
	s.queues={}
	for name,probe in pairs({ci=function() return queues.ci(command) end,
		builds=function() return queues.builds(p,command,s.uptime_seconds,config.build_runtime or (p.runtime or '/run/user/unknown')..'/build-budget') end}) do
		local worked,value=pcall(probe)
		if worked then s.queues[name]=value else s.probe_errors[#s.probe_errors+1]=name..' queue probe unavailable' end
	end
	local mounts=config.mounts or {'/','/home','/nix','/tmp'}
	local args={'df','-Pk'}; for _,path in ipairs(mounts) do args[#args+1]=path end
	s.disks=probes.parse_df(command(args))
	local seen={}; for _,d in ipairs(s.disks) do seen[d.mount]=true end
	for _,path in ipairs(mounts) do if not seen[path] then s.probe_errors[#s.probe_errors+1]='missing filesystem '..path end end
	local lists=command({'zpool','list','-Hp','-o','name,health,size,alloc,free,cap'})
	local status=command({'zpool','status','-p'})
	local errors={}; local current
	for line in status:gmatch('[^\n]+') do
		local name=line:match('^%s*pool:%s*(%S+)'); if name then current=name; errors[current]=0 end
		if current then
			local _,r,w,c=line:match('^%s*(%S+)%s+%S+%s+(%d+)%s+(%d+)%s+(%d+)%s*$')
			if r then errors[current]=errors[current]+tonumber(r)+tonumber(w)+tonumber(c) end
			if line:find('errors:') and not line:find('No known data errors',1,true) then errors[current]=errors[current]+1 end
		end
	end
	for line in lists:gmatch('[^\n]+') do
		local name,health,cap=line:match('^(%S+)%s+(%S+)%s+%d+%s+%d+%s+%d+%s+(%d+)')
		if name then
			s.pools[#s.pools+1]={name=name,health=errors[name] and health or 'UNKNOWN',capacity=tonumber(cap),errors=errors[name]}
		end
	end
	s.zfs_status=status:sub(1,12000)
	if config.gpu~=false then
		local gpu=command({'nvidia-smi','--query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total','--format=csv,noheader,nounits'})
		local detail=command({'nvidia-smi','-q','-d','TEMPERATURE,PERFORMANCE'})
		local limits={}; for block in detail:gmatch('GPU [^\n]+\n(.-)\n\n') do limits[#limits+1]=block end
		if #limits==0 then limits={detail} end
		for line in gpu:gmatch('[^\n]+') do
			local index,name,temp,used,memory_used,memory_total=line:match('^(%d+),%s*(.-),%s*([%d.]+),%s*([%d.]+),%s*([%d.]+),%s*([%d.]+)')
			if index then
				local d=limits[tonumber(index)+1] or ''
				s.gpus[#s.gpus+1]={name=name,temperature=tonumber(temp),used_percent=tonumber(used),memory_used_mib=tonumber(memory_used),memory_total_mib=tonumber(memory_total),
					max_temperature=tonumber(d:match('GPU Max Operating Temp%s*:%s*(%d+)')),thermal_slowdown=d:match('SW Thermal Slowdown%s*:%s*Active')~=nil}
			end
		end
		if #s.gpus==0 then s.probe_errors[#s.probe_errors+1]='GPU metrics unavailable' end
		for _,g in ipairs(s.gpus) do if not g.max_temperature then s.probe_errors[#s.probe_errors+1]='GPU operating limit unavailable' end end
	end
	for key,path in pairs({memory_full='/proc/pressure/memory',io_full='/proc/pressure/io'}) do
		s.pressure[key]=tonumber(read(path):match('full[^\n]-avg300=([%d.]+)'))
		if not s.pressure[key] then s.probe_errors[#s.probe_errors+1]='pressure probe unavailable: '..key end
	end
	local processes=command({'ps','-eo','comm,pcpu,pmem','--sort=-pcpu'})
	s.training=processes:match('\n%s*ocrz%-train%s')~=nil
	local top={}; for line in processes:gmatch('[^\n]+') do if #top<9 then top[#top+1]=line end end
	s.top_processes=table.concat(top,'\n')
	local journal=command({'journalctl','-k','-b','--since','-3 hours','-n','200','--no-pager','-o','cat'})
	for line in journal:gmatch('[^\n]+') do if M.notable(line) and #s.kernel_errors<10 then s.kernel_errors[#s.kernel_errors+1]=line:sub(1,240) end end
	local finish=cpu(read('/proc/stat')); local total=finish.total-start.total
	s.cpu={used_percent=total>0 and math.floor(100*(1-(finish.idle-start.idle)/total)+0.5) or nil,
		load_per_cpu=(tonumber(read('/proc/loadavg'):match('^%S+%s+(%S+)')) or 0)/finish.count,logical_cpus=finish.count}
	if not s.cpu.used_percent then s.probe_errors[#s.probe_errors+1]='CPU utilization unavailable' end
	return s
end
return M
