local json=require("cjson")
local fs=require("notifications.fs")
local model=require("notifications.model")
local ffi=require("ffi")
ffi.cdef[[void *popen(const char *,const char *); unsigned long fread(void *,unsigned long,unsigned long,void *); int ferror(void *); int pclose(void *);]]
local M={}
local function quote(s) return "'"..tostring(s):gsub("'","'\\''").."'" end
function M.command(argv,input)
	local parts={} for _,s in ipairs(argv) do parts[#parts+1]=quote(s) end
	local command=table.concat(parts," ").." 2>/dev/null"
	if input then command=command.." < "..quote(input) end
	local p=ffi.C.popen(command,"r"); assert(p~=nil,"process unavailable")
	local chunks,total={},0; local buffer=ffi.new("char[4096]")
	while true do
		local n=tonumber(ffi.C.fread(buffer,1,4096,p)); if n==0 then break end
		total=total+n
		if total<=2097152 then chunks[#chunks+1]=ffi.string(buffer,n) end
	end
	local failed=ffi.C.ferror(p)~=0; local status=ffi.C.pclose(p)
	assert(not failed and status==0 and total<=2097152,"adapter command failed or exceeded output limit")
	return table.concat(chunks)
end
local function sql_quote(value) return "'"..tostring(value):gsub("'","''").."'" end
local function sql(database,statement,readonly)
	local args={"sqlite3","-json","-cmd",".timeout 5000","-cmd","PRAGMA synchronous=FULL;"}
	if readonly then args[#args+1]="-readonly" end
	args[#args+1]=database
	local input
	if #statement>32768 then
		input=database..".statement"; fs.atomic(input,statement,384)
	else args[#args+1]=statement end
	local bytes=M.command(args,input)
	if input then fs.unlink(input) end
	return bytes=="" and {} or json.decode(bytes)
end
function M.init_feed(feed)
	fs.mkdir(feed,488)
	local db=feed.."/events.sqlite3"
	sql(db,"CREATE TABLE IF NOT EXISTS events(sequence INTEGER PRIMARY KEY AUTOINCREMENT,event_id TEXT UNIQUE NOT NULL,payload TEXT NOT NULL);")
	fs.chmod(db,416); fs.sync(db)
	return db
end
local function base(state)
	fs.mkdir(state,448)
	local a={now=os.time(),boundary=function() end}
	local db=state.."/state.sqlite3"
	sql(db,"CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY,payload TEXT NOT NULL); CREATE INDEX IF NOT EXISTS state_status ON state(json_extract(payload,'$.status'),key); CREATE TABLE IF NOT EXISTS jobs(sequence INTEGER PRIMARY KEY,event_id TEXT UNIQUE NOT NULL,payload TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'active',last_attempt INTEGER); CREATE INDEX IF NOT EXISTS jobs_pending ON jobs(state,last_attempt,sequence);")
	fs.chmod(db,384); fs.sync(db)
	function a.load(key)
		local rows=sql(db,"SELECT payload FROM state WHERE key="..sql_quote(key)..";",true)
		return rows[1] and json.decode(rows[1].payload)
	end
	function a.save(key,value)
		sql(db,"INSERT INTO state VALUES("..sql_quote(key)..","..sql_quote(json.encode(value))..") ON CONFLICT(key) DO UPDATE SET payload=excluded.payload;")
		fs.sync(db)
	end
	a.database=db
	function a.identity(e)
		fs.atomic(state.."/.identity-input",model.key(e),384)
		return M.command({"sha256sum",state.."/.identity-input"}):match("^%x+")
	end
	return a
end
M.store=base
function M.status(state)
	local a=base(state)
	local rows=sql(a.database,"SELECT key,payload FROM state WHERE json_extract(payload,'$.status') IN ('pending','sending','unresolved','uncertain','exhausted') ORDER BY key LIMIT 100;",true)
	local deliveries={}
	for _,r in ipairs(rows) do local d=json.decode(r.payload); d.bytes=nil; d.id=r.key:sub(10); deliveries[#deliveries+1]=d end
	local counts=sql(a.database,"SELECT json_extract(payload,'$.status') AS status,count(*) AS count FROM state WHERE json_extract(payload,'$.status') IS NOT NULL GROUP BY json_extract(payload,'$.status');",true)
	return {deliveries=deliveries,counts=counts,limit=100,wake="unsupported",acknowledgement="unconfirmed"}
end
function M.retry(state,id,allow_duplicate)
	local a=base(state)
	local d=assert(a.load("delivery-"..id),"unknown delivery")
	assert(d.status~="delivered","completed deliveries cannot be retried")
	assert(d.status~="sending" and (d.status~="uncertain" or allow_duplicate),"uncertain retry requires --allow-duplicate")
	if d.status=="pending" and d.attempts==0 then return end
	d.operator_retries=(d.operator_retries or 0)+1
	assert(d.operator_retries<=3,"operator retry limit reached; inspect durable state")
	d.status="pending"; d.attempts=0; d.next_attempt=nil
	sql(a.database,"BEGIN IMMEDIATE; UPDATE state SET payload="..sql_quote(json.encode(d)).." WHERE key="..sql_quote("delivery-"..id).."; UPDATE jobs SET state='active',last_attempt=0 WHERE event_id="..sql_quote(id:gsub("%-%a+$","")).."; COMMIT;")
	fs.sync(a.database)
end
function M.exporter(database,state,feed)
	local a=base(state)
	local feed_db=M.init_feed(feed)
	local function query(sql)
		local bytes=M.command({"sqlite3","-readonly","-json","-cmd",".timeout 5000",database,sql})
		return bytes=="" and {} or json.decode(bytes)
	end
	function a.latest() return query("SELECT coalesce(max(rowid),0) AS sequence FROM ci_runs;")[1].sequence end
	function a.results(after,limit)
		-- Targets and terminal runs come from one read snapshot; never a partial target set.
		local rows=query("SELECT rowid AS sequence,substr(run_id,1,161) AS run_id,substr(repository,1,203) AS repository,substr(ref,1,257) AS ref,substr(commit_sha,1,41) AS commit_sha,status,substr(failure_stage,1,80) AS failure_stage,started_at,finished_at,(SELECT json_group_array(json_object('target',target,'status',status)) FROM (SELECT substr(target,1,201) AS target,status FROM ci_targets WHERE run_id=ci_runs.run_id ORDER BY ordinal LIMIT 33)) AS targets_json FROM ci_runs WHERE rowid>"..assert(tonumber(after)).." ORDER BY rowid LIMIT "..assert(tonumber(limit))..";")
		for _,r in ipairs(rows) do r.targets=json.decode(r.targets_json); r.targets_json=nil end
		return rows or {}
	end
	function a.export(id,e)
		sql(feed_db,"INSERT INTO events(event_id,payload) VALUES("..sql_quote(id)..","..sql_quote(json.encode(e))..") ON CONFLICT(event_id) DO NOTHING;")
		fs.sync(feed_db)
	end
	return a
end
local function origin(path)
	local ok,url=pcall(M.command,{"git","-C",path,"config","--local","--no-includes","--get","remote.origin.url"})
	if not ok then return nil end
	url=url:gsub("\n$",""):gsub("%.git$","")
	return url:match("^git@github%.com:([%w_.%-]+/[%w_.%-]+)$") or url:match("^https://github%.com/([%w_.%-]+/[%w_.%-]+)$") or url:match("^ssh://git@github%.com/([%w_.%-]+/[%w_.%-]+)$")
end
function M.dispatcher(config,state,feed,writer,now)
	assert(type(config.owner)=="string" and config.owner:match("^[%w_%-]+$"),"owner required")
	assert(type(config.roots)=="table" and #config.roots>0,"trusted roots required")
	local a=base(state); a.now=now or os.time()
	a.admin=fs.route(config.adminInbox)
	local checkouts={}; local root_identities={}
	local previous=a.load("roots")
	local boot=fs.read("/proc/sys/kernel/random/boot_id",64)
	for _,root in ipairs(config.roots) do
		root_identities[root]=fs.route(root).identity
		assert(not previous or previous.boot~=boot or previous.identities[root]==root_identities[root],"trusted root changed; inspect routing state before resetting")
		for _,name in ipairs(fs.files(root)) do
			local path=root.."/"..name
			if pcall(fs.route,path) then
				local repo=origin(path)
				if repo then checkouts[#checkouts+1]={repository=repo,path=path,root=root,identity=fs.route(path).identity} end
			end
		end
	end
	if not previous or previous.boot~=boot then a.save("roots",{boot=boot,identities=root_identities}) end
	a.metrics={decoded=0}
	function a.list()
		local cursor=a.load("ingest") or {sequence=0}
		local feed_db=feed.."/events.sqlite3"
		local incoming=sql(feed_db,"SELECT sequence,event_id,payload FROM events WHERE sequence>"..cursor.sequence.." ORDER BY sequence LIMIT 100;",true)
		-- Import and its cursor share one FULL-synchronous SQLite transaction.
		local transaction={"BEGIN IMMEDIATE;"}
		for _,r in ipairs(incoming) do
			transaction[#transaction+1]="INSERT INTO jobs(event_id,payload) VALUES("..sql_quote(r.event_id)..","..sql_quote(r.payload)..") ON CONFLICT(event_id) DO NOTHING;"
			cursor.sequence=r.sequence
		end
		transaction[#transaction+1]="INSERT INTO state VALUES('ingest',"..sql_quote(json.encode(cursor))..") ON CONFLICT(key) DO UPDATE SET payload=excluded.payload; COMMIT;"
		sql(a.database,table.concat(transaction,"\n")); fs.sync(a.database)
		local new=sql(a.database,"SELECT sequence,payload FROM jobs WHERE state='active' AND last_attempt IS NULL ORDER BY sequence LIMIT 100;",true)
		local retries=sql(a.database,"SELECT sequence,payload FROM jobs WHERE state='active' AND last_attempt IS NOT NULL ORDER BY last_attempt,sequence LIMIT 100;",true)
		local events={}
		-- New jobs first; both selections have independent budgets.
		for _,row in ipairs(new) do events[#events+1]=row end
		for _,row in ipairs(retries) do events[#events+1]=row end
		for i,row in ipairs(events) do
			local e=json.decode(row.payload); e._queue_id=row.sequence
			a.metrics.decoded=a.metrics.decoded+1
			events[i]=e
		end
		return events
	end
	function a.complete(e,project_status,admin_status)
		local function active(s) return s=="pending" or s=="unresolved" or s=="sending" end
		local state_value=(active(project_status) or active(admin_status)) and "active" or "settled"
		sql(a.database,"UPDATE jobs SET state="..sql_quote(state_value)..",last_attempt="..a.now.." WHERE sequence="..assert(tonumber(e._queue_id))..";")
		fs.sync(a.database)
	end
	function a.resolve(e)
		local path,reason=model.route(e.repository,config.owner,checkouts,config.overrides or {})
		if not path then return nil,reason end
		local ok,route=pcall(function()
			for _,c in ipairs(checkouts) do
				if c.path==path then
					assert(fs.route(c.root).identity==root_identities[c.root] and fs.route(path).identity==c.identity,"canonical root changed")
				end
			end
			fs.mkdir(path.."/inbox",448)
			return fs.route(path.."/inbox")
		end)
		if ok then return route end
		return nil,"unsafe or changed checkout"
	end
	function a.stage(id,e,role,reason)
		local dir=state.."/stage-"..id; fs.mkdir(dir,448)
		local notes=fs.files(dir,".frontmatter.md")
		assert(#notes<=1,"ambiguous private stage")
		if #notes==0 then
			local body=dir.."/body"; fs.atomic(body,model.render(e,role,reason),384)
			-- Only the trusted writer is executed. Its printed path is not authority.
			local date=e.finished_at~="unknown" and e.finished_at or "1970-01-01T00:00:00Z"
			local ok=pcall(M.command,{writer,"--inbox",dir,"--sender","mechatron-prime","--recipient",role,
				"--subject","CI failure "..id,"--description","Exact-run CI failure requiring inspection.",
				"--datetime",date,"--type","status","--response-expected","false","--priority","high","--tag","ci"},body)
			notes=fs.files(dir,".frontmatter.md")
			assert(#notes==1,ok and "writer did not publish a note" or "writer failed before staging")
		end
		local path=dir.."/"..notes[1]; fs.sync(path)
		return fs.read(path,32768)
	end
	a.probe=fs.probe; a.publish=fs.publish
	return a
end
return M
