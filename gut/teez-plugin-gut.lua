local DEFAULT_INCLUDE = { "**/*_test.gd", "**/test/**/*.gd" }
local DEFAULT_GUT_SCRIPT = "addons/gut/gut_cmdln.gd"

local function trim(value)
	if not value then
		return value
	end
	return value:match("^%s*(.-)%s*$")
end

local function strip_ansi(line)
	return line:gsub("%\27%[[0-9;]*[A-Za-z]", "")
end

local function dirname(path)
	local parent = path:match("^(.*)/[^/]+$")
	if parent and parent ~= "" then
		return parent
	end
	return "."
end

local function find_project_root(path)
	local dir = path
	while dir and dir ~= "" and dir ~= "/" do
		if fs.exists(dir .. "/project.godot") then
			return dir
		end
		dir = dirname(dir)
	end
	return path
end

local function resolve_godot_command(context)
	local runner = context.runner or {}
	if runner.command then
		return runner.command
	end

	local godot4 = sys.run("which", { "godot4" })
	if godot4.exit_code == 0 and trim(godot4.stdout) ~= "" then
		return "godot4"
	end

	return "godot"
end

local function resolve_gut_script(project_root, context)
	local runner = context.runner or {}
	if runner.gut_script then
		return runner.gut_script
	end
	if fs.exists(project_root .. "/" .. DEFAULT_GUT_SCRIPT) then
		return DEFAULT_GUT_SCRIPT
	end
	error("GUT not found at " .. DEFAULT_GUT_SCRIPT .. " (install the gut addon or set runners.gut.gut_script)")
end

local function collect_include_patterns(context)
	local runner = context.runner or {}
	if runner.include and #runner.include > 0 then
		return runner.include
	end
	return DEFAULT_INCLUDE
end

local function collect_exclude_patterns(context)
	local runner = context.runner or {}
	return runner.exclude or {}
end

local function is_excluded(path, patterns)
	for _, pattern in ipairs(patterns) do
		if filter.glob_match(path, pattern) then
			return true
		end
	end
	return false
end

local function to_res_path(project_root, file_path)
	local root = project_root
	if root:sub(-1) == "/" then
		root = root:sub(1, -2)
	end

	if file_path:sub(1, #root + 1) == root .. "/" then
		local rel = file_path:sub(#root + 2):gsub("\\", "/")
		return "res://" .. rel
	end

	if file_path:match("^res://") then
		return file_path
	end

	return file_path:gsub("\\", "/")
end

local function discover_test_files(context)
	local patterns = collect_include_patterns(context)
	local excludes = collect_exclude_patterns(context)
	local seen = {}
	local tests = {}

	for _, pattern in ipairs(patterns) do
		for _, file in ipairs(fs.glob(context.target_path, pattern)) do
			if not seen[file] and not is_excluded(file, excludes) then
				seen[file] = true
				table.insert(tests, file)
			end
		end
	end

	table.sort(tests)
	return tests
end

local function apply_filters(tests, filters)
	if not filters then
		return tests
	end

	local filtered = {}
	for _, id in ipairs(tests) do
		if filter.matches({ id = id }, filters) then
			table.insert(filtered, id)
		end
	end
	return filtered
end

local function append_args(args, extra)
	if not extra then
		return
	end
	for _, value in ipairs(extra) do
		table.insert(args, value)
	end
end

local function build_gut_args(context, project_root, tests)
	local runner = context.runner or {}
	local gut_args = { "-gexit" }

	if runner.gut_prefix then
		table.insert(gut_args, "-gprefix=" .. runner.gut_prefix)
	end
	if runner.gut_suffix then
		table.insert(gut_args, "-gsuffix=" .. runner.gut_suffix)
	elseif runner.gut_suffix == nil then
		table.insert(gut_args, "-gsuffix=_test.gd")
	end
	if runner.gut_include_subdirs then
		table.insert(gut_args, "-ginclude_subdirs")
	end

	append_args(gut_args, runner.gut_args)

	if context.filters then
		if context.filters.name and context.filters.name ~= "" then
			table.insert(gut_args, "-gselect=" .. context.filters.name)
		end
		if context.filters.pattern and context.filters.pattern ~= "" then
			table.insert(gut_args, "-gunit_test_name=" .. context.filters.pattern)
		end
	end

	if runner.gut_dir then
		table.insert(gut_args, "-gdir=" .. runner.gut_dir)
		return gut_args
	end

	if tests and #tests == 1 then
		table.insert(gut_args, "-gtest=" .. to_res_path(project_root, tests[1]))
		return gut_args
	end

	if tests and #tests > 1 then
		for _, test_file in ipairs(tests) do
			table.insert(gut_args, "-gtest=" .. to_res_path(project_root, test_file))
		end
		return gut_args
	end

	if runner.test_dir then
		table.insert(gut_args, "-gdir=" .. runner.test_dir)
	else
		table.insert(gut_args, "-gdir=res://test")
	end

	return gut_args
end

local function build_godot_spec(context, tests)
	local project_root = find_project_root(context.target_path)
	local runner = context.runner or {}
	local args = { "--headless" }

	append_args(args, runner.args)

	table.insert(args, "-s")
	table.insert(args, resolve_gut_script(project_root, context))

	append_args(args, build_gut_args(context, project_root, tests))

	return {
		command = resolve_godot_command(context),
		args = args,
		cwd = project_root,
	}
end

function list(context)
	local tests = discover_test_files(context)
	return apply_filters(tests, context.filters)
end

function build_command(context)
	local tests = discover_test_files(context)
	tests = apply_filters(tests, context.filters)
	return build_godot_spec(context, tests)
end

function parse_line(line)
	if not line or line == "" then
		return nil
	end

	local text = strip_ansi(line)

	local passed = text:match("%[Passed%][:]?%s+(.+)")
	if passed then
		local id = trim(passed:match("^(.-)%s*%(") or passed)
		local duration_ms = passed:match("%(([%d%.]+)s%)")
		local event = { event = "pass", id = id }
		if duration_ms then
			event.duration_ms = math.floor((tonumber(duration_ms) or 0) * 1000)
		end
		return event
	end

	local failed = text:match("%[Failed%][:]?%s+(.+)")
	if failed then
		return { event = "fail", id = trim(failed), msg = text }
	end

	local pending = text:match("%[Pending%][:]?%s+(.+)")
	if pending then
		return { event = "skip", id = trim(pending) }
	end

	local risky = text:match("%[Risky%][:]?%s+(.+)")
	if risky then
		return { event = "skip", id = trim(risky), msg = text }
	end

	if text:match("^Passed:?%s+") then
		local id = trim(text:match("^Passed:?%s+(.+)"))
		return { event = "pass", id = id }
	end

	if text:match("^Failed:?%s+") then
		local id = trim(text:match("^Failed:?%s+(.+)"))
		return { event = "fail", id = id, msg = text }
	end

	if text:match("^%s*%-%s+%[.-%]%s+") then
		return { event = "output", text = line }
	end

	return { event = "output", text = line }
end

function build_coverage_run(context)
	local runner = context.runner or {}
	local coverage = runner.coverage
	if not coverage then
		return nil
	end

	local tests = apply_filters(discover_test_files(context), context.filters)
	local spec = build_godot_spec(context, tests)
	local coverage_path = coverage.path or coverage.output or "coverage/godot"

	table.insert(spec.args, 1, "--coverage")
	table.insert(spec.args, 2, "--coverage-path=" .. coverage_path)

	if coverage.packages then
		for _, package in ipairs(coverage.packages) do
			table.insert(spec.args, "--coverage-package=" .. package)
		end
	end

	local report = coverage.report or (coverage_path .. "/coverage.json")
	local reporter = coverage.reporter or "json"

	return {
		command = spec.command,
		args = spec.args,
		cwd = spec.cwd,
		env = spec.env,
		report = report,
		reporter = reporter,
		min_line_rate = coverage.min_line_rate,
	}
end
