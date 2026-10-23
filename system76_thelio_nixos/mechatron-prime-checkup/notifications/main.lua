local dir=arg[0]:match("^(.*)/[^/]+$") or "."
package.path=dir.."/../?.lua;"..package.path
local json=require("cjson")
local function help()
	print("mechatron-prime-notifications 0.1.0 (Linux): durable private CI failure delivery")
	print("Usage: mechatron-prime-notifications export|dispatch|status|retry --state DIR [options]")
	print("  export: --database FILE --feed DIR [--replay 1..100]")
	print("  dispatch: --config PRIVATE_JSON --feed DIR [--writer EXECUTABLE]")
	print("  status: JSON delivery states; wake/ack remain unconfirmed")
	print("  retry: --id HEX-project|HEX-admin [--allow-duplicate]")
	print("  --allow-duplicate explicitly permits one retry of an uncertain delivery")
end
if arg[1]=="--help" or arg[1]=="-h" then help(); return end
if arg[1]=="--about" then print("mechatron-prime-notifications 0.1.0: durable CI failure delivery (Linux/"..require("jit").arch..")"); return end
local mode=arg[1]; local options={}
local allowed={state=true,database=true,feed=true,config=true,writer=true,replay=true,id=true}
local i=2
while i<=#arg do
	local key=arg[i]:match("^%-%-(.+)$")
	if key=="allow-duplicate" then options[key]=true
	elseif allowed[key] and arg[i+1] then i=i+1; options[key]=arg[i]
	else io.stderr:write("Invalid notification option. Use --help.\n"); os.exit(2) end
	i=i+1
end
local replay=options.replay and tonumber(options.replay)
if not ({export=true,dispatch=true,status=true,retry=true})[mode] or not options.state
	or (mode=="export" and (not options.database or not options.feed))
	or (mode=="dispatch" and (not options.config or not options.feed))
	or (options.replay and (mode~="export" or not replay or replay<1 or replay>100 or replay~=math.floor(replay)))
	or (mode=="retry" and (not options.id or not options.id:match("^%x+%-%a+$"))) then
	io.stderr:write("Missing or invalid notification arguments. Use --help.\n"); os.exit(2)
end
local fs=require("notifications.fs")
local adapters=require("notifications.adapters")
local engine=require("notifications.engine")
local function status()
	return adapters.status(options.state)
end
local unlock
local ok,err=pcall(function()
	fs.mkdir(options.state,448)
	unlock=fs.lock(options.state.."/.lock")
	assert(unlock,"another notification operation owns the lock")
	if mode=="export" then engine.export(adapters.exporter(options.database,options.state,options.feed),replay)
	elseif mode=="dispatch" then
		local config=json.decode(fs.private_config(options.config))
		engine.dispatch(adapters.dispatcher(config,options.state,options.feed,options.writer or "llmsend-write-note"))
	elseif mode=="retry" then
		adapters.retry(options.state,options.id,options["allow-duplicate"])
	end
	if mode=="status" then print(json.encode(status()))
	elseif mode~="export" then print(json.encode({operation=mode,status="completed",wake="unsupported",acknowledgement="unconfirmed"})) end
end)
if unlock then unlock() end
if not ok then io.stderr:write("Notification operation failed: "..tostring(err).."\n"); os.exit(1) end
