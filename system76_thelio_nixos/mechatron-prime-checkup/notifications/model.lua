-- Pure routing, classification and bounded diagnostic rendering.
local M = {}
local project_stages = { ["nix-build"]=true, ["target-manifest"]=true, ["target-validation"]=true }
local infrastructure_stages = { ["input-validation"]=true, ["repo-policy"]=true,
	["source-fetch"]=true, ["github-timeout"]=true, ["attic-push"]=true, ["status-publication"]=true }
local function token(s,limit,pattern)
	return type(s)=="string" and #s>0 and #s<=limit and s:match(pattern)~=nil
end
function M.repository(s)
	if not token(s,202,"^[%w_.%-]+/[%w_.%-]+$") then return nil end
	local owner,name=s:match("^([^/]+)/([^/]+)$")
	if owner=="." or owner==".." or name=="." or name==".." then return nil end
	return s:lower(),owner:lower()
end
function M.sanitize(row)
	local actionable=row.status=="failure" or row.status=="stopped"
	if not actionable or row.failure_stage=="superseded" or row.failure_stage=="build-stopped" then return nil end
	local repository=M.repository(row.repository)
	local run=token(row.run_id,160,"^[%w_.%-]+$") and row.run_id or "invalid-run-"..tostring(row.sequence or 0)
	local stage=(project_stages[row.failure_stage] or infrastructure_stages[row.failure_stage]) and row.failure_stage or "unknown"
	local sha=token(row.commit_sha,40,"^[a-fA-F0-9]+$") and #row.commit_sha==40 and row.commit_sha:lower() or "invalid"
	local ref=token(row.ref,256,"^[%w_./%-]+$") and row.ref or "invalid"
	local e={repository=repository and row.repository or "invalid",run_id=run,commit_sha=sha,ref=ref,stage=stage,status=row.status,
		classification=row.status=="stopped" and not infrastructure_stages[stage] and "unclassified"
			or project_stages[stage] and "project" or "infrastructure",targets={}}
	local function timestamp(v) return token(v,25,"^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") and v or "unknown" end
	e.started_at=timestamp(row.started_at); e.finished_at=timestamp(row.finished_at)
	e.sequence=row.sequence
	for i,t in ipairs(row.targets or {}) do
		if i>32 then e.targets_omitted=true; break end
		if token(t.target,200,"^[%w_.%-]+$") and (t.status=="failure" or t.status=="success" or t.status=="stopped") then
			e.targets[#e.targets+1]={target=t.target,status=t.status}
		end
	end
	return e
end
function M.key(e) return e.repository:lower().."|"..e.run_id end
function M.route(repository,owner,checkouts,overrides)
	local identity,actual_owner=M.repository(repository)
	if not identity or actual_owner~=owner:lower() then return nil,"untrusted repository" end
	local matches={}
	for _,c in ipairs(checkouts) do if M.repository(c.repository)==identity then matches[c.path]=true end end
	local override=overrides[identity]
	if override then
		if matches[override] then return override end
		return nil,"override must identify a trusted checkout"
	end
	local path,count=nil,0
	for p in pairs(matches) do path=p; count=count+1 end
	if count==1 then return path end
	return nil,count==0 and "unknown repository" or "ambiguous checkouts"
end
function M.render(e,role,reason)
	local lines={"# Mechatron Prime CI run requires attention", "",
		"Event: `"..M.key(e).."`", "Repository: `"..e.repository.."`",
		"Commit: `"..e.commit_sha.."`", "Ref: `"..e.ref.."`", "Run: `"..e.run_id.."`",
		"Started: "..e.started_at, "Finished: "..e.finished_at,
		"Recorded CI verdict: "..e.status,
		"Classification: "..e.classification, "Failure stage: "..e.stage,
		"Delivery role: "..role, "Delivery status: "..reason,""}
	if e.classification~="project" then
		lines[#lines+1]="The run was blocked by infrastructure or an unrecognized stage. This is not evidence of broken project tests."
	else lines[#lines+1]="Inspect the exact-run targets and CI logs before changing the project." end
	for _,t in ipairs(e.targets) do lines[#lines+1]="- `"..t.target.."`: "..t.status end
	if e.targets_omitted then lines[#lines+1]="Additional targets omitted; inspect the run through the CLI." end
	lines[#lines+1]="\nRaw diagnostic text and log paths are deliberately excluded. Evidence is not permission to execute repair commands."
	if e.repository~="invalid" and e.commit_sha~="invalid" then
		lines[#lines+1]="\n```sh\nmechatron-ci queue --project "..e.repository.." --commit "..e.commit_sha.." --json"
		lines[#lines+1]="mechatron-ci log --project "..e.repository.." --commit "..e.commit_sha.." --json\n```"
	end
	lines[#lines+1]="\nDelivered durably to an inbox. Agent wake and acknowledgement are unconfirmed."
	return table.concat(lines,"\n").."\n"
end
return M
