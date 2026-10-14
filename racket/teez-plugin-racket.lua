local DEFAULT_INCLUDE = {
	"**/test/**",
	"**/*-test.rkt",
	"**/*_test.rkt",
}

local parse_state = {
	in_failure = false,
	failure_name = nil,
	failure_location = nil,
	failure_lines = {},
	current_file = nil,
}

local function trim(s)
	return (s:match("^%s*(.-)%s*$"))
end

local function merge_patterns(context)
	local patterns = {}
	local seen = {}

	local function add(pattern)
		if pattern and pattern ~= "" and not seen[pattern] then
			seen[pattern] = true
			table.insert(patterns, pattern)
		end
	end

	for _, pattern in ipairs(DEFAULT_INCLUDE) do
		add(pattern)
	end

	local runner = context.runner or {}
	if runner.include then
		for _, pattern in ipairs(runner.include) do
			add(pattern)
		end
	end

	return patterns
end

local function excluded(path, context)
	local runner = context.runner or {}
	local excludes = runner.exclude or {}
	for _, pattern in ipairs(excludes) do
		if filter.glob_match(path, pattern) then
			return true
		end
	end
	return false
end

local function is_test_file(path)
	return path:match("%.rkt$")
		and (
			path:match("/test/")
			or path:match("/test$")
			or path:match("%-test%.rkt$")
			or path:match("_test%.rkt$")
		)
end

local function discover_tests(context)
	local root = context.target_path
	local patterns = merge_patterns(context)
	local tests = {}
	local seen = {}

	for _, pattern in ipairs(patterns) do
		for _, path in ipairs(fs.glob(root, pattern)) do
			if is_test_file(path) and not excluded(path, context) and not seen[path] then
				seen[path] = true
				table.insert(tests, path)
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

local function resolve_targets(context)
	local runner = context.runner or {}
	if runner.targets and #runner.targets > 0 then
		return runner.targets
	end

	if context.filters then
		local listed = list({ target_path = context.target_path, runner = runner })
		if #listed > 0 then
			return listed
		end
	end

	return { context.target_path }
end

local function coverage_submodule(cov)
	if type(cov) == "string" then
		return cov
	end
	if type(cov) == "table" and cov.submodule then
		return cov.submodule
	end
	return "cover"
end

local function reset_failure_state()
	parse_state.in_failure = false
	parse_state.failure_name = nil
	parse_state.failure_location = nil
	parse_state.failure_lines = {}
end

local function flush_failure()
	if not parse_state.in_failure then
		return nil
	end

	local id = parse_state.failure_location or parse_state.failure_name or parse_state.current_file or "rackunit"
	local msg = table.concat(parse_state.failure_lines, "\n")
	if msg == "" then
		msg = "rackunit failure"
	end

	reset_failure_state()
	return { event = "fail", id = id, msg = msg }
end

function list(context)
	local tests = {}
	local list_args = { "test", "--list", context.target_path }

	local ok, output = pcall(function()
		return sys.exec("raco", list_args)
	end)

	if ok and output then
		for line in output:gmatch("[^\r\n]+") do
			line = trim(line)
			if line ~= "" and not line:match("^Usage:") then
				table.insert(tests, line)
			end
		end
	end

	if #tests == 0 then
		tests = discover_tests(context)
	end

	return apply_filters(tests, context.filters)
end

function build_command(context)
	local runner = context.runner or {}
	local args = { "test" }

	if runner.args then
		for _, arg in ipairs(runner.args) do
			table.insert(args, arg)
		end
	end

	if not runner.quiet then
		local has_verbose = false
		for _, arg in ipairs(args) do
			if arg == "-v" or arg == "--verbose" then
				has_verbose = true
				break
			end
		end
		if not has_verbose then
			table.insert(args, "-v")
		end
	end

	if runner.check_stderr then
		table.insert(args, "--check-stderr")
	end

	for _, target in ipairs(resolve_targets(context)) do
		table.insert(args, target)
	end

	return {
		command = "raco",
		args = args,
		cwd = runner.cwd,
		env = runner.env,
	}
end

function build_coverage_run(context)
	local runner = context.runner or {}
	local cov = runner.coverage
	if not cov then
		return nil
	end

	local run = build_command(context)
	local submodule = coverage_submodule(cov)
	local cover_args = { "cover" }

	if type(cov) == "table" and cov.directory then
		table.insert(cover_args, cov.directory)
	else
		table.insert(cover_args, context.target_path)
	end

	table.insert(cover_args, "++" .. submodule)

	if type(cov) == "table" then
		if cov.exclude then
			for _, pattern in ipairs(cov.exclude) do
				table.insert(cover_args, "--exclude")
				table.insert(cover_args, pattern)
			end
		end
		if cov.include then
			for _, pattern in ipairs(cov.include) do
				table.insert(cover_args, "--include")
				table.insert(cover_args, pattern)
			end
		end
		if cov.args then
			for _, arg in ipairs(cov.args) do
				table.insert(cover_args, arg)
			end
		end
	end

	return {
		command = run.command,
		args = run.args,
		cwd = run.cwd,
		env = run.env,
		collect = {
			command = "raco",
			args = cover_args,
		},
		report = (type(cov) == "table" and cov.report) or "coverage/lcov.info",
		reporter = (type(cov) == "table" and cov.reporter) or "lcov",
		output = type(cov) == "table" and cov.output,
		min_line_rate = type(cov) == "table" and cov.min_line_rate,
	}
end

function parse_line(line)
	line = trim(line)
	if line == "" then
		return nil
	end

	if line:match("^%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-%-$") then
		if parse_state.in_failure then
			return flush_failure()
		end
		parse_state.in_failure = true
		parse_state.failure_name = nil
		parse_state.failure_location = nil
		parse_state.failure_lines = {}
		return nil
	end

	if parse_state.in_failure then
		local name = line:match("^name:%s+(.+)$")
		if name then
			parse_state.failure_name = name
			return nil
		end

		local location = line:match("^location:%s+(.+)$")
		if location then
			parse_state.failure_location = location
			return nil
		end

		table.insert(parse_state.failure_lines, line)
		return nil
	end

	local running = line:match("^Running%s+(.+%.rkt)$")
	if running then
		parse_state.current_file = running
		return { event = "start", id = running }
	end

	local file_colon = line:match("^([^%s]+%.rkt):$")
	if file_colon then
		parse_state.current_file = file_colon
		return { event = "start", id = file_colon }
	end

	local inline_failure = line:match("^%s*Failure%s*%(([^)]+)%):%s*(.+)$")
	if inline_failure then
		local location, msg = inline_failure
		return { event = "fail", id = location, msg = msg }
	end

	if line:match("^%s*good%s*$") and parse_state.current_file then
		return { event = "pass", id = parse_state.current_file }
	end

	local named_pass = line:match("^%s*%[([^%]]+)%].*good%s*$")
	if named_pass and parse_state.current_file then
		return { event = "pass", id = parse_state.current_file .. "::" .. named_pass }
	end

	if line:match("^racket/unit%-test:") then
		local id = parse_state.current_file or "rackunit"
		return { event = "fail", id = id, msg = line }
	end

	if line:match("^ERROR") or line:match("^exception") then
		local id = parse_state.current_file or "rackunit"
		return { event = "fail", id = id, msg = line }
	end

	local failures = line:match("(%d+)%s+failures?%.?$")
	if failures and tonumber(failures) > 0 then
		return { event = "output", text = line }
	end

	local successes = line:match("(%d+)%s+tests?%.?$") or line:match("(%d+)%s+successes?%.?$")
	if successes then
		return { event = "output", text = line }
	end

	return { event = "output", text = line }
end
