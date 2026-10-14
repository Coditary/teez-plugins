local DEFAULT_INCLUDE = {
	"**/*_test.gd",
	"**/*_test.tscn",
	"**/test/**/*.gd",
	"**/test/**/*.tscn",
}

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

local function discover_test_targets(context)
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

local function append_test_filters(args, context)
	local runner = context.runner or {}
	append_args(args, runner.test_args)

	if not context.filters then
		return
	end

	if context.filters.name and context.filters.name ~= "" then
		local flag = runner.test_name_flag or "--unit-test-filter"
		table.insert(args, flag .. "=" .. context.filters.name)
	end

	if context.filters.pattern and context.filters.pattern ~= "" then
		local flag = runner.test_pattern_flag or "--unit-test-filter"
		table.insert(args, flag .. "=" .. context.filters.pattern)
	end
end

local function append_selected_targets(args, project_root, tests, context)
	local runner = context.runner or {}
	local scene_flag = runner.scene_flag or "--scene"
	local script_flag = runner.test_file_flag or "--unit-test-file"

	for _, target in ipairs(tests) do
		local res_path = to_res_path(project_root, target)
		if res_path:match("%.tscn$") then
			table.insert(args, scene_flag)
			table.insert(args, res_path)
		else
			table.insert(args, script_flag)
			table.insert(args, res_path)
		end
	end
end

local function build_godot_spec(context, tests)
	local project_root = find_project_root(context.target_path)
	local runner = context.runner or {}
	local args = { "--headless", "--path", project_root }

	append_args(args, runner.args)

	if runner.script then
		table.insert(args, "-s")
		table.insert(args, runner.script)
		append_test_filters(args, context)
		if tests and #tests > 0 then
			append_selected_targets(args, project_root, tests, context)
		end
	else
		table.insert(args, "--test")
		append_test_filters(args, context)
		if tests and #tests > 0 then
			append_selected_targets(args, project_root, tests, context)
		end
	end

	return {
		command = resolve_godot_command(context),
		args = args,
		cwd = project_root,
	}
end

function list(context)
	local tests = discover_test_targets(context)
	return apply_filters(tests, context.filters)
end

function build_command(context)
	local tests = discover_test_targets(context)
	tests = apply_filters(tests, context.filters)
	return build_godot_spec(context, tests)
end

function parse_line(line)
	if not line or line == "" then
		return nil
	end

	local text = strip_ansi(line)

	local passed_colon = text:match("^%s*PASSED:?%s+(.+)$")
	if passed_colon then
		local id = trim(passed_colon:match("^(.-)%s*%(") or passed_colon)
		local duration_s = passed_colon:match("%(([%d%.]+)s%)")
		local event = { event = "pass", id = id }
		if duration_s then
			event.duration_ms = math.floor((tonumber(duration_s) or 0) * 1000)
		end
		return event
	end

	local failed_colon = text:match("^%s*FAILED:?%s+(.+)$")
	if failed_colon then
		local id = trim(failed_colon:match("^(.-)%s*%(") or failed_colon)
		return { event = "fail", id = id, msg = text }
	end

	local skipped_colon = text:match("^%s*SKIPPED:?%s+(.+)$")
	if skipped_colon then
		return { event = "skip", id = trim(skipped_colon) }
	end

	local method_id, duration_s = text:match("^%s*(%S+)%s+PASSED%s*%(([%d%.]+)s%)")
	if method_id then
		local event = { event = "pass", id = method_id }
		if duration_s then
			event.duration_ms = math.floor((tonumber(duration_s) or 0) * 1000)
		end
		return event
	end

	local failed_id = text:match("^%s*(%S+)%s+FAILED%s*%(([%d%.]+)s%)")
	if failed_id then
		return { event = "fail", id = failed_id, msg = text }
	end

	local bracket_pass = text:match("%[Passed%][:]?%s+(.+)")
	if bracket_pass then
		local id = trim(bracket_pass:match("^(.-)%s*%(") or bracket_pass)
		local duration_s = bracket_pass:match("%(([%d%.]+)s%)")
		local event = { event = "pass", id = id }
		if duration_s then
			event.duration_ms = math.floor((tonumber(duration_s) or 0) * 1000)
		end
		return event
	end

	local bracket_fail = text:match("%[Failed%][:]?%s+(.+)")
	if bracket_fail then
		return { event = "fail", id = trim(bracket_fail), msg = text }
	end

	local ok_bracket = text:match("%[%s*OK%s*%]%s+(.+)")
	if ok_bracket then
		return { event = "pass", id = trim(ok_bracket) }
	end

	local fail_bracket = text:match("%[%s*FAIL%s*%]%s+(.+)")
	if fail_bracket then
		return { event = "fail", id = trim(fail_bracket), msg = text }
	end

	if text:match("^res://") then
		return { event = "start", id = trim(text) }
	end

	if text:match("^Tests finished:") or text:match("^Running %d+ tests") then
		return { event = "output", text = line }
	end

	if text:match("^%s+Error:") or text:match("^%s+at:") then
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

	local tests = apply_filters(discover_test_targets(context), context.filters)
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
