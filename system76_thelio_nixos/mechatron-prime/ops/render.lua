local cjson = require("cjson.safe")

local M = {}

local function html_escape(value)
	local escaped = tostring(value or "")
	escaped = escaped:gsub("&", "&amp;")
	escaped = escaped:gsub("<", "&lt;")
	escaped = escaped:gsub(">", "&gt;")
	escaped = escaped:gsub('"', "&quot;")
	escaped = escaped:gsub("'", "&#39;")
	return escaped
end

local function json_array(values)
	if #values == 0 then
		return cjson.empty_array
	end
	return values
end

local function ci_current_json(current)
	if type(current) ~= "table" then return nil end
	if type(current.repo) ~= "string" or type(current.sha) ~= "string" then return nil end
	return {
		state = current.state or "unknown",
		repository = current.repo,
		commit_sha = current.sha,
		target = current.target or "",
		started_at = current.started_at or "",
		pending = current.pending or 0,
	}
end

local function ci_queue_jobs(runs)
	local jobs = {}
	for _, run in ipairs(runs or {}) do
		jobs[#jobs + 1] = {
			repository = run.repository,
			commit_sha = run.commit_sha,
			queued_at = run.queued_at or "",
		}
	end
	return jobs
end

--- Render the monitoring contract as a deliberately small JSON document so
--- health clients receive checks and issues without unrelated host details.
function M.health_json(model)
	local checks = {}
	for _, check in ipairs(model.health.checks or {}) do
		checks[#checks + 1] = check
	end
	local issues = {}
	for _, issue in ipairs(model.health.issues or {}) do
		issues[#issues + 1] = issue
	end
	local encoded, encode_error = cjson.encode({
		status = model.health.status,
		generated_at = model.generated_at,
		checks = json_array(checks),
		issues = json_array(issues),
	})
	if not encoded then
		error("could not encode health JSON: " .. tostring(encode_error))
	end
	return encoded .. "\n"
end

--- Render the narrow agent-facing CI projection; private ledger paths,
--- output paths, delivery IDs, and arbitrary SQL remain server-side.
function M.ci_json(model)
	local mechatron = model.mechatron
	local recent = {}
	for _, run in ipairs(mechatron.recent or {}) do recent[#recent + 1] = run end
	local encoded, encode_error = cjson.encode({
		generated_at = model.generated_at,
		admission = mechatron.admission,
		worker = {
			state = mechatron.worker_state,
			queue_depth = mechatron.queue_depth,
			current = ci_current_json(mechatron.current),
		},
		recent = json_array(recent),
	})
	if not encoded then error("could not encode CI JSON: " .. tostring(encode_error)) end
	return encoded .. "\n"
end

--- Render the active worker claim and the still-waiting FIFO separately.  A
--- batch is atomically moved out of the physical queue before it builds, so
--- collapsing these lists would give clients a misleading empty queue.
function M.ci_queue_json(generated_at, queue)
	local encoded, encode_error = cjson.encode({
		generated_at = generated_at,
		admission = queue.admission,
		worker = {
			state = queue.worker_state,
			current = ci_current_json(queue.current),
		},
		claimed = json_array(ci_queue_jobs(queue.claimed)),
		waiting = json_array(ci_queue_jobs(queue.waiting)),
	})
	if not encoded then error("could not encode CI queue JSON: " .. tostring(encode_error)) end
	return encoded .. "\n"
end

--- Whitelist the bounded history API fields so storage-only metadata cannot
--- escape if the ledger schema or system adapter grows later.
function M.ci_history_json(generated_at, runs)
	local results = {}
	for _, run in ipairs(runs or {}) do
		results[#results + 1] = {
			repository = run.repository,
			commit_sha = run.commit_sha,
			status = run.status,
			failure_stage = run.failure_stage or "",
			failure_detail = run.failure_detail or "",
			started_at = run.started_at,
			finished_at = run.finished_at,
		}
	end
	local encoded, encode_error = cjson.encode({
		generated_at = generated_at,
		results = json_array(results),
	})
	if not encoded then error("could not encode CI history JSON: " .. tostring(encode_error)) end
	return encoded .. "\n"
end

--- Render a state pill.  The optional label lets a state carry a readable
--- caption ("muted till reboot") while keeping a single hyphen-free token in
--- the CSS class, since the state doubles as the class name.
local function status_badge(state, label)
	return '<span class="status status-' .. html_escape(state) .. '">' .. html_escape(label or state) .. "</span>"
end

local function action_forms(actions)
	local forms = {}
	for _, action in ipairs(actions or {}) do
		local attributes = action.danger and ' data-confirm="This will interrupt active work. Continue?"' or ""
		local class = action.danger and "action danger" or "action"
		forms[#forms + 1] = string.format('<form method="post" action="%s"%s><button class="%s" type="submit">%s</button></form>',
			html_escape(action.path), attributes, class, html_escape(action.label))
	end
	if #forms == 0 then return "" end
	return '<div class="actions">' .. table.concat(forms, "") .. "</div>"
end

local function model_section(label, models, available, empty_message)
	local body
	if not available then
		body = '<p class="quiet model-state">Unavailable</p>'
	elseif #(models or {}) == 0 then
		body = '<p class="quiet model-state">' .. html_escape(empty_message) .. "</p>"
	else
		local items = {}
		for _, model in ipairs(models) do
			items[#items + 1] = "<li><code>" .. html_escape(model.name) .. "</code></li>"
		end
		body = '<ul class="model-list">' .. table.concat(items, "") .. "</ul>"
	end
	return '<section class="model-section"><h4>' .. html_escape(label) .. "</h4>" .. body .. "</section>"
end

local function service_cards(services)
	local cards = {}
	for _, service in ipairs(services or {}) do
		cards[#cards + 1] = string.format([[
		<article class="card">
			<div class="card-heading"><h3>%s</h3>%s</div>
			<p>%s</p>%s%s%s
		</article>]], html_escape(service.label), status_badge(service.state), html_escape(service.detail),
			service.models and model_section("Installed models", service.models, service.model_inventory_available, "No installed models") or "",
			service.loaded_models and model_section("Loaded now", service.loaded_models, service.loaded_models_available, "No models currently loaded") or "",
			action_forms(service.actions))
	end
	return table.concat(cards, "\n")
end

local function error_list(errors)
	if #(errors or {}) == 0 then
		return '<p class="quiet">No recent system errors.</p>'
	end
	local items = {}
	for _, message in ipairs(errors) do
		items[#items + 1] = "<li><code>" .. html_escape(message) .. "</code></li>"
	end
	return '<ul class="errors">' .. table.concat(items, "") .. "</ul>"
end

--- Render one self-contained operations page from an immutable snapshot; all
--- probe output crosses a single HTML-escaping boundary before display.
function M.page(model)
	local current_build = "Idle"
	if model.mechatron.current then
		current_build = model.mechatron.current.repo .. " @ " .. model.mechatron.current.sha
	end

	return string.format([[<!doctype html>
<html lang="en">
<head>
	<meta charset="utf-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>Mechatron Prime Operations</title>
	<style>
		:root { color-scheme: dark; --bg:#090d14; --panel:#111925; --line:#263449; --text:#e8eef7; --muted:#94a3b8; --accent:#63d6a4; --warn:#f4c56a; --bad:#ff7474; }
		* { box-sizing:border-box; }
		body { margin:0; background:radial-gradient(circle at top,#162235 0,#090d14 48%%); color:var(--text); font:15px/1.5 system-ui,sans-serif; }
		main { width:min(1600px,calc(100%% - 32px)); margin:32px auto 64px; }
		header { display:flex; align-items:end; justify-content:space-between; gap:24px; margin-bottom:24px; }
		h1 { margin:0; font-size:clamp(1.7rem,4vw,2.7rem); letter-spacing:-.04em; }
		h2,h3,p { margin-top:0; }
		.eyebrow { color:var(--accent); font-weight:700; letter-spacing:.12em; text-transform:uppercase; }
		.quiet { color:var(--muted); }
		.tabs { display:flex; gap:8px; overflow:auto; padding-bottom:2px; border-bottom:1px solid var(--line); }
		.tabs button { border:0; border-radius:8px 8px 0 0; padding:10px 15px; background:transparent; color:var(--muted); cursor:pointer; font:inherit; }
		.tabs button.active { color:var(--text); background:var(--panel); box-shadow:inset 0 -2px var(--accent); }
		.panel { display:none; padding-top:22px; }
		.panel.active { display:block; }
		.grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(250px,1fr)); gap:14px; }
		.stack { display:grid; grid-template-columns:minmax(0,1fr); gap:14px; }
		.card { min-width:0; padding:18px; border:1px solid var(--line); border-radius:13px; background:linear-gradient(145deg,rgba(20,31,46,.96),rgba(13,20,31,.96)); box-shadow:0 14px 40px rgba(0,0,0,.18); }
		.card-heading { display:flex; justify-content:space-between; gap:12px; align-items:start; }
		.card h3 { margin-bottom:8px; font-size:1rem; }
		.model-section { margin-top:14px; }
		.model-section h4 { margin:0; color:var(--muted); font-size:.76rem; font-weight:700; letter-spacing:.08em; text-transform:uppercase; }
		.status { display:inline-block; border:1px solid currentColor; border-radius:999px; padding:2px 8px; font:700 .72rem/1.4 ui-monospace,monospace; text-transform:uppercase; }
		.status-active,.status-healthy,.status-waiting,.status-chiming { color:var(--accent); }
		/* A deliberate mute is amber, not red: the chime is silent because
		   somebody chose that, which is a different thing from a fault. */
		.status-degraded,.status-resilvering,.status-inactive,.status-muted,.status-muted-till-reboot { color:var(--warn); }
		.status-critical,.status-failed,.status-stopped { color:var(--bad); }
		dl { display:grid; grid-template-columns:max-content 1fr; gap:8px 18px; margin:0; }
		dt { color:var(--muted); }
		dd { margin:0; min-width:0; overflow-wrap:anywhere; }
		pre,code { font-family:ui-monospace,SFMono-Regular,Consolas,monospace; }
		pre { margin:0; padding:16px; border:1px solid var(--line); border-radius:10px; background:#070a0f; overflow:auto; white-space:pre; }
		.errors { padding-left:20px; color:var(--warn); }
		.model-list { margin:7px 0 0; padding-left:20px; color:var(--muted); }
		.model-list li { overflow-wrap:anywhere; }
		.model-state { margin:7px 0 0; }
		.actions { display:flex; flex-wrap:wrap; gap:8px; margin-top:14px; }
		.actions form { margin:0; }
		.action { border:1px solid var(--line); border-radius:8px; padding:7px 11px; background:#172336; color:var(--text); cursor:pointer; font:inherit; }
		.action:hover { border-color:var(--accent); }
		.action.danger { color:#ffb0b0; }
		@media (max-width:620px) { header { align-items:start; flex-direction:column; } dl { grid-template-columns:1fr; gap:2px; } dd { margin-bottom:10px; } }
	</style>
</head>
<body>
<main>
	<header>
		<div><div class="eyebrow">Thelio · Tailnet only</div><h1>Mechatron Prime Operations</h1><p class="quiet">Snapshot generated %s</p></div>
		%s
	</header>
	<nav class="tabs" aria-label="Operations sections">
		<button class="active" data-tab="services">Services</button>
		<button data-tab="os">OS</button>
		<button data-tab="zfs">ZFS</button>
		<button data-tab="resources">Resource Consumption</button>
	</nav>
	<section class="panel active" data-panel="services">
		<div class="grid">
			<article class="card"><div class="card-heading"><h3>Mechatron worker</h3>%s</div><dl><dt>Current build</dt><dd>%s</dd><dt>Queue depth</dt><dd>%s</dd></dl>%s</article>
			<article class="card"><div class="card-heading"><h3>Grandfather clock</h3>%s</div><dl><dt>Schedule</dt><dd>%s</dd><dt>Next run</dt><dd>%s</dd><dt>Declarative source</dt><dd><code>%s</code></dd></dl>%s</article>
			<article class="card"><div class="card-heading"><h3>FSearch database</h3>%s</div><dl><dt>Schedule</dt><dd>%s</dd><dt>Next run</dt><dd>%s</dd></dl>%s</article>
			%s
		</div>
		<h2>Recent errors</h2>%s
	</section>
	<section class="panel" data-panel="os"><article class="card"><dl><dt>NixOS</dt><dd>%s</dd><dt>Uptime</dt><dd>%s</dd><dt>Memory</dt><dd>%s</dd><dt>Filesystems</dt><dd>%s</dd></dl></article></section>
	<section class="panel" data-panel="zfs"><div class="stack"><article class="card"><div class="card-heading"><h3>Pool health</h3>%s</div><p>%s</p></article><article class="card"><h3>Pools</h3><pre>%s</pre></article></div></section>
	<section class="panel" data-panel="resources"><div class="stack"><article class="card"><h3>hogs</h3><pre>%s</pre></article><article class="card"><h3>Network hogs</h3><pre>%s</pre></article><article class="card"><h3>Steam shader precomputation</h3>%s</article></div></section>
</main>
<script>
document.querySelectorAll('.tabs button').forEach((button) => button.addEventListener('click', () => {
	document.querySelectorAll('.tabs button,.panel').forEach((node) => node.classList.remove('active'));
	button.classList.add('active');
	document.querySelector('[data-panel="' + button.dataset.tab + '"]').classList.add('active');
}));
document.querySelectorAll('form[data-confirm]').forEach((form) => form.addEventListener('submit', (event) => {
	if (!window.confirm(form.dataset.confirm)) event.preventDefault();
}));
</script>
</body>
</html>
]],
		html_escape(model.generated_at),
		status_badge(model.health.status),
		-- Halted admission outranks the worker's own state, and is deliberately
		-- shown in the alarm colour rather than the warning colour: a normally
		-- idle worker is already "inactive" in amber, so amber here would be
		-- indistinguishable from healthy idleness.
		status_badge(model.mechatron.admission.state == "halted" and "stopped" or model.mechatron.worker_state),
		html_escape(current_build),
		html_escape(model.mechatron.queue_depth),
		action_forms({
			{label = "Drain queue", path = "/ops/actions/mechatron-worker/start"},
			{label = "Halt CI", path = "/ops/actions/mechatron-worker/halt", danger = true},
			{label = "Resume CI", path = "/ops/actions/mechatron-worker/resume"},
			{label = "Cancel build", path = "/ops/actions/mechatron-worker/stop", danger = true},
		}),
		status_badge(model.clocksound.chime.state, model.clocksound.chime.label),
		html_escape(model.clocksound.schedule),
		html_escape(model.clocksound.next_run),
		html_escape(model.clocksound.source),
		-- Run-state controls only. The schedule above stays read-only because
		-- NixOS owns it; muting changes when the chime sounds, never when it is
		-- declared to sound.
		action_forms({
			{label = "Mute till reboot", path = "/ops/actions/clocksound/mute-until-reboot"},
			{label = "Mute", path = "/ops/actions/clocksound/mute"},
			{label = "Unmute", path = "/ops/actions/clocksound/unmute"},
		}),
		status_badge(model.fsearch.state),
		html_escape(model.fsearch.schedule),
		html_escape(model.fsearch.next_run),
		action_forms({{label = "Rebuild now", path = "/ops/actions/fsearch/run"}}),
		service_cards(model.services),
		error_list(model.recent_errors),
		html_escape(model.os.nixos_version),
		html_escape(model.os.uptime),
		html_escape(model.os.memory),
		html_escape(model.os.disks),
		status_badge(model.zfs.status),
		html_escape(model.zfs.detail),
		html_escape(model.zfs.pools),
		html_escape(model.resources.hogs),
		html_escape(model.resources.network_hogs),
		status_badge(model.resources.steam_shader)
	)
end

--- Render a short-lived action result, notably a Codex pairing code, behind
--- the same escaping boundary as host probe output.
function M.action_result(title, result)
	return string.format([[<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>%s</title>
<style>:root{color-scheme:dark}body{margin:0;background:#090d14;color:#e8eef7;font:16px/1.5 system-ui,sans-serif}main{width:min(720px,calc(100%% - 32px));margin:12vh auto}.card{padding:24px;border:1px solid #263449;border-radius:13px;background:#111925}pre{white-space:pre-wrap;overflow-wrap:anywhere;padding:16px;background:#070a0f;border-radius:8px}a{color:#63d6a4}</style></head>
<body><main><article class="card"><h1>%s</h1><pre>%s</pre><p><a href="/ops/">Return to Operations</a></p></article></main></body></html>]],
		html_escape(title), html_escape(title), html_escape(result ~= "" and result or "Completed."))
end

return M
