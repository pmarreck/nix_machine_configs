local M = {}

-- Only a repository identity and a read-only flag cross the client boundary.
function M.validate(request)
	if type(request) ~= "table" then return nil, "invalid request" end
	for key in pairs(request) do
		if key ~= "repository" and key ~= "dry_run" then return nil, "unknown field" end
	end
	if type(request.repository) ~= "string" then return nil, "repository required" end
	if request.dry_run ~= nil and type(request.dry_run) ~= "boolean" then return nil, "invalid dry_run" end
	local name = request.repository
	if name:sub(1,9) == "pmarreck/" then name = name:sub(10) end
	if #name < 1 or #name > 100 or not name:match("^[A-Za-z0-9._-]+$") or name == "." or name == ".." then
		return nil, "invalid owned repository"
	end
	return {repository="pmarreck/" .. name:lower(),dry_run=request.dry_run == true}
end

return M
