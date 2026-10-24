#!/usr/bin/env bash

# The vendored Mechatron Prime operations console is assembled from individually
# pinned files, so a scoped update can pair a newer module with an older one that
# lacks a function it calls. Digest pins cannot see that. Load the vendored tree
# as the ops package does and exercise every probe through a recording adapter.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
VENDORED="$ROOT_DIR/system76_thelio_nixos/mechatron-prime"
failures=0
total=0

pass() { total=$((total + 1)); printf 'ok - %s\n' "$1"; }
fail() { total=$((total + 1)); failures=$((failures + 1)); printf 'not ok - %s\n' "$1" >&2; }

if ! command -v luajit >/dev/null 2>&1; then
	fail 'luajit is required to load the vendored operations console'
	printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
	exit "$failures"
fi

output="$(cd "$VENDORED" && luajit - "$VENDORED" <<'LUA' 2>&1
local vendored = arg[1]
package.path = vendored .. "/?.lua;" .. package.path
local adapter = {
	capture = function(argv)
		local call = table.concat(argv, "|")
		if call:find("|stat|", 1, true) then return "8180:12\n", true end
		if call:find("|app-server|daemon|version", 1, true) then return '{"status":"running"}', true end
		if call:find("results.sqlite3", 1, true) then return '[{"repository":"pmarreck/validate","status":"success"}]', true end
		return "active\n", true
	end,
	read = function(path) return "read:" .. path end,
	now = function() return "2026-10-24T04:00:00Z" end,
	euid = function() return 0 end,
}
local ok, system = pcall(function() return require("ops.system").new(adapter) end)
if not ok then print("LOAD-FAIL " .. tostring(system)) os.exit(1) end
local probed = 0
for name, member in pairs(system) do
	if type(member) == "function" and name ~= "read" then
		local called, err = pcall(member)
		if not called then print("PROBE-FAIL " .. name .. ": " .. tostring(err)) os.exit(1) end
		probed = probed + 1
	end
end
local health_ok, health_err = pcall(function() return require("ops.health") end)
if not health_ok then print("LOAD-FAIL ops.health: " .. tostring(health_err)) os.exit(1) end
print("PROBES " .. probed)
LUA
)"
status=$?

if [ "$status" -eq 0 ]; then
	pass 'vendored operations console probes run against a recording adapter'
else
	fail "vendored operations console is inconsistent: $(printf '%s' "$output" | tail -n 1)"
fi

case "$output" in
	PROBES\ [1-9]*) pass "every system probe executed ($output)" ;;
	*) fail "expected a probe count, got [$output]" ;;
esac

printf '%d/%d assertions passed\n' "$((total - failures))" "$total"
exit "$failures"
