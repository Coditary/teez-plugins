local DEFAULT_INCLUDE = { "**/tests/**/*.ahk", "**/*_test.ahk" }
local DEFAULT_EXCLUDE = { "**/*.teez.lua" }

local AUNIT_MARKERS = {
	"AUnit",
	"TestCase",
	"@Test",
	"Assert%.",
	"extends%s+TestCase",
}

local function normalize_path(path)
	return (path or ""):gsub("\\", "/")
end

local function merged_patterns(context, key, defaults)
	local runner = context.runner or {}
	local patterns = runner[key]
	if patterns == nil then
		return defaults
	end
	if type(patterns) == "string" then
		return { patterns }
	end
	return patterns
end

local function path_excluded(path, excludes)
	for _, pattern in ipairs(excludes) do
		if filter.glob_match(path, pattern) then
			return true
		end
	end
	return false
end

local function looks_like_aunit_test(path)
	local file = io.open(path, "r")
	if not file then
		return true
	end
	local content = file:read("*a")
	file:close()
	if not content or content == "" then
		return false
	end
	for _, marker in ipairs(AUNIT_MARKERS) do
		if content:match(marker) then
			return true
		end
	end
	return false
end

local function to_test_id(root, path)
	root = normalize_path(root)
	path = normalize_path(path)
	if path:sub(1, #root + 1) == root .. "/" then
		return path:sub(#root + 2)
	end
	return path
end

local function collect_test_files(context)
	local root = context.target_path
	local includes = merged_patterns(context, "include", DEFAULT_INCLUDE)
	local excludes = merged_patterns(context, "exclude", DEFAULT_EXCLUDE)
	local seen = {}
	local files = {}

	for _, pattern in ipairs(includes) do
		for _, path in ipairs(fs.glob(root, pattern)) do
			local normalized = normalize_path(path)
			if not seen[normalized] and not path_excluded(normalized, excludes) then
				seen[normalized] = true
				if looks_like_aunit_test(path) then
					table.insert(files, path)
				end
			end
		end
	end

	table.sort(files)
	return files
end

local function filter_test_ids(context, files)
	local ids = {}
	for _, path in ipairs(files) do
		local id = to_test_id(context.target_path, path)
		local descriptor = { id = id, path = normalize_path(path) }
		if not context.filters or filter.matches(descriptor, context.filters) then
			table.insert(ids, { id = id, path = path })
		end
	end
	return ids
end

local function resolve_command(context)
	local runner = context.runner or {}
	return runner.command or "AutoHotkey.exe"
end

local function append_args(base, extra)
	local args = {}
	for _, value in ipairs(base or {}) do
		table.insert(args, value)
	end
	for _, value in ipairs(extra or {}) do
		table.insert(args, value)
	end
	return args
end

local function escape_ahk_string(value)
	return (value or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
end

local function write_temp_runner(content)
	local tmp = os.getenv("TEMP") or os.getenv("TMP") or "/tmp"
	local path = normalize_path(tmp) .. "/teez-aunit-runner-" .. tostring(os.time()) .. ".ahk"
	local file = assert(io.open(path, "w"))
	file:write(content)
	file:close()
	return path
end

local function build_generated_runner(context, entries, mode)
	local runner = context.runner or {}
	local root = escape_ahk_string(normalize_path(context.target_path))
	local lines = {
		"#Requires AutoHotkey v2.0",
		"#SingleInstance Force",
		'SetWorkingDir("' .. root .. '")',
	}

	if runner.aunit_include then
		table.insert(lines, '#Include "' .. escape_ahk_string(runner.aunit_include) .. '"')
	else
		table.insert(lines, "#Include <AUnit>")
	end

	for _, entry in ipairs(entries) do
		local rel = escape_ahk_string(entry.id)
		table.insert(lines, '#Include "' .. rel .. '"')
	end

	if mode == "list" then
		for _, entry in ipairs(entries) do
			table.insert(lines, 'FileAppend("' .. escape_ahk_string(entry.id) .. '\\n", "*")')
		end
		table.insert(lines, "ExitApp(0)")
	else
		if runner.setup then
			table.insert(lines, runner.setup)
		end
		table.insert(lines, "AUnit.Run()")
	end

	return table.concat(lines, "\n")
end

local function build_run_spec(context, mode)
	local runner = context.runner or {}
	local entries = filter_test_ids(context, collect_test_files(context))

	if runner.runner and fs.exists(runner.runner) then
		local args = append_args(runner.args, { runner.runner })
		if mode == "list" then
			table.insert(args, "--teez-list")
		end
		for _, entry in ipairs(entries) do
			table.insert(args, entry.id)
		end
		return {
			command = resolve_command(context),
			args = args,
			cwd = runner.cwd,
		}
	end

	local script = build_generated_runner(context, entries, mode)
	local runner_path = write_temp_runner(script)
	local args = append_args(runner.args, { runner_path })
	return {
		command = resolve_command(context),
		args = args,
		cwd = runner.cwd or context.target_path,
	}
end

function list(context)
	local ids = {}
	for _, entry in ipairs(filter_test_ids(context, collect_test_files(context))) do
		table.insert(ids, entry.id)
	end
	return ids
end

function build_command(context)
	return build_run_spec(context, "run")
end

function build_list_command(context)
	return build_run_spec(context, "list")
end

function build_coverage_run(context)
	local runner = context.runner or {}
	local coverage = runner.coverage
	if not coverage then
		return nil
	end

	local spec = build_run_spec(context, "run")
	if coverage.env then
		spec.env = coverage.env
	end
	if coverage.args then
		spec.args = append_args(spec.args, coverage.args)
	end
	if coverage.cwd then
		spec.cwd = coverage.cwd
	end
	if coverage.collect then
		spec.collect = coverage.collect
	end
	if coverage.report then
		spec.report = coverage.report
	end
	if coverage.reporter then
		spec.reporter = coverage.reporter
	end
	if coverage.output then
		spec.output = coverage.output
	end
	if coverage.min_line_rate then
		spec.min_line_rate = coverage.min_line_rate
	end
	return spec
end

local function trim(value)
	return (value or ""):match("^%s*(.-)%s*$")
end

function parse_line(line)
	if line == nil or line == "" then
		return nil
	end

	local duration_ms = line:match("(%d+%.?%d*)%s*ms%s*$")
	local stripped = duration_ms and line:sub(1, #line - #duration_ms - 3) or line

	local id, msg = stripped:match("^%[(.-)%]%s+FAIL:?%s*(.*)$")
	if id then
		return {
			event = "fail",
			id = trim(id),
			msg = trim(msg ~= "" and msg or line),
			duration_ms = duration_ms and tonumber(duration_ms) or nil,
		}
	end

	id = stripped:match("^%[(.-)%]%s+PASS%s*$")
	if id then
		return {
			event = "pass",
			id = trim(id),
			duration_ms = duration_ms and tonumber(duration_ms) or nil,
		}
	end

	id = stripped:match("^PASS:?%s+(.+)$")
	if id then
		return {
			event = "pass",
			id = trim(id),
			duration_ms = duration_ms and tonumber(duration_ms) or nil,
		}
	end

	id, msg = stripped:match("^FAIL:?%s+([^%-:]+)%s*[-:]%s*(.*)$")
	if id then
		return {
			event = "fail",
			id = trim(id),
			msg = trim(msg ~= "" and msg or line),
			duration_ms = duration_ms and tonumber(duration_ms) or nil,
		}
	end

	id = stripped:match("^FAIL:?%s+(.+)$")
	if id then
		return {
			event = "fail",
			id = trim(id),
			msg = line,
			duration_ms = duration_ms and tonumber(duration_ms) or nil,
		}
	end

	id = stripped:match("^SKIP:?%s+(.+)$")
	if id then
		return { event = "skip", id = trim(id) }
	end

	if stripped:match("^Running %d+ test") or stripped:match("^%d+ tests? %a+") then
		return { event = "output", text = line }
	end

	return { event = "output", text = line }
end
