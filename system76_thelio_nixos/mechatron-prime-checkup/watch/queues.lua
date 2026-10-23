-- Read-only queue adapters and pure advisory classification. Age is not proof of a hang.
local json=require('cjson.safe')
local M={}
local function array(value) return type(value)=='table' end
function M.ci(command)
	local bytes=command({'mechatron-ci','queue','--json'})
	assert(#bytes<=32768,'CI queue exceeds snapshot byte bound')
	local value=assert(json.decode(bytes),'invalid CI queue JSON')
	assert(type(value.worker)=='table' and array(value.waiting) and array(value.claimed)
		and type(value.admission)=='table' and type(value.admission.state)=='string','incomplete CI queue')
	if value.worker.current==json.null then value.worker.current=nil end
	assert(value.worker.current==nil or type(value.worker.current)=='table','invalid CI current job')
	assert(#value.waiting+#value.claimed<=256,'CI queue exceeds snapshot bound')
	for _,job in ipairs(value.waiting) do assert(type(job.waiting_seconds)=='number' and job.waiting_seconds>=0,'invalid CI waiting age') end
	return value
end
function M.builds(p,command,uptime,runtime)
	assert(type(uptime)=='number','uptime unavailable for build queue')
	local locks=assert(json.decode(command({'lslocks','--json','--output','PID,MODE,PATH,BLOCKER',
		'--filter','PATH =~ "/build-budget/slot-[0-9]+[.]lock$"'})),'invalid build lock JSON')
	assert(type(locks.locks)=='table','build lock list unavailable')
	local processes,parents={},{}
	for line in command({'ps','-eo','pid=,ppid=,etimes=,comm='}):gmatch('[^\n]+') do
		local pid,parent,age,name=line:match('^%s*(%d+)%s+(%d+)%s+(%d+)%s+(%S+)%s*$')
		if pid then
			pid,parent=tonumber(pid),tonumber(parent)
			processes[pid]={pid=pid,parent=parent,age_seconds=tonumber(age),name=name}
			if name=='build-budget' then parents[parent]=true end
		end
	end
	assert(next(processes),'process inventory unavailable')
	local held={}
	for _,lock in ipairs(locks.locks) do
		if type(lock.path)=='string' and lock.path:sub(1,#runtime+1)==runtime..'/' and lock.path:match('/slot%-%d+%.lock$') and lock.mode=='WRITE' then
			held[lock.pid]=true
		end
	end
	local result={holders={},waiting={},scopes={}}
	for pid,process in pairs(processes) do
		if process.name=='build-budget' and not parents[pid] then
			local cmd=p.read('/proc/'..pid..'/cmdline')
			if cmd then
				local args={}; for part in cmd:gmatch('([^%z]+)%z') do args[#args+1]=part end
				local project='unknown'
				for i=2,#args do
					if args[i]=='--' then break end
					if args[i]=='--project' and args[i+1] and args[i+1]:match('^[%w_%-]+$') then project=args[i+1] end
				end
				local row={pid=pid,project=project,age_seconds=process.age_seconds}
				local target=held[pid] and result.holders or result.waiting
				target[#target+1]=row
			end
		end
	end
	assert(#result.holders+#result.waiting<=128,'build queue exceeds snapshot bound')
	for _,list in ipairs({result.holders,result.waiting}) do table.sort(list,function(a,b) return a.age_seconds>b.age_seconds end) end
	local output=command({'systemctl','--user','show','build-*.scope','-p','Id','-p','ActiveState',
		'-p','ActiveEnterTimestampMonotonic','-p','CPUUsageNSec','-p','TasksCurrent'})
	for block in (output..'\n\n'):gmatch('(.-)\n\n') do
		local fields={}; for key,value in block:gmatch('([%w]+)=([^\n]*)') do fields[key]=value end
		if fields.ActiveState=='active' and fields.Id and fields.Id:match('^build%-%w[%w_%-]*%.scope$') then
			local started=tonumber(fields.ActiveEnterTimestampMonotonic)
			local cpu,tasks=tonumber(fields.CPUUsageNSec),tonumber(fields.TasksCurrent)
			assert(started and cpu and tasks,'build scope counters unavailable')
			result.scopes[#result.scopes+1]={id=fields.Id,cpu_ns=cpu,tasks=tasks,age_seconds=math.max(0,math.floor(uptime-started/1000000))}
		end
	end
	assert(#result.scopes<=128,'scope inventory exceeds snapshot bound')
	return result
end
function M.issues(current,previous,compare)
	local issues={}
	local function add(id,detail) issues[#issues+1]={id='queue:'..id,severity='warning',detail=detail} end
	if not current then return issues end
	local builds=current.builds
	if builds then
		for _,job in ipairs(builds.waiting) do
			if job.age_seconds>=1800 then add('build:wait',job.project..' PID '..job.pid..' waiting about '..job.age_seconds..'s; admission fairness needs review') end
		end
		if #builds.scopes==0 then
			for _,job in ipairs(builds.holders) do if job.age_seconds>=60 then add('build:holder','slot held by '..job.project..' without a reported running build scope; inspect before release') end end
		end
		local old={}; for _,scope in ipairs(previous and previous.builds and previous.builds.scopes or {}) do old[scope.id]=scope end
		for _,scope in ipairs(builds.scopes) do
			if scope.age_seconds>=1800 then add('build:runtime',scope.id..' running '..scope.age_seconds..'s; review runtime allowance') end
			if compare and old[scope.id] and old[scope.id].cpu_ns==scope.cpu_ns then
				add('build:progress',scope.id..' CPU counter unchanged since previous check; inspect I/O and descendants before declaring stuck')
			end
		end
	end
	local ci=current.ci
	if ci and ci.admission.state~='halted' then
		local active=ci.worker.current
		if active and (active.elapsed_seconds or 0)>=1800 then add('ci:runtime',(active.repository or 'CI job')..' running '..active.elapsed_seconds..'s; review runtime allowance') end
		for _,job in ipairs(ci.waiting) do
			if job.waiting_seconds>=1800 then add('ci:wait',(job.repository or 'CI job')..' waiting '..job.waiting_seconds..'s')
			elseif not active and job.waiting_seconds>=300 then add('ci:idle','queued work with no reported current job; inspect watcher and claims') end
		end
		if compare and active and previous and previous.ci and previous.ci.worker.current then
			local old=previous.ci.worker.current
			if active.repository==old.repository and active.commit_sha==old.commit_sha and active.started_at==old.started_at and active.target==old.target then
				add('ci:progress','same CI commit and target since previous check; progress is unconfirmed, not proof of a hang')
			end
		end
	end
	return issues
end
return M
