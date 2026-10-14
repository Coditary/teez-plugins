local pending_failure = nil

local DEFAULT_INCLUDE = {
	"**/test/**/*_test.rb",
	"**/test/**/test_*.rb",
}

local DEFAULT_EXCLUDE = {
	"**/*.teez.lua",
}

local function runner_cfg(context)
	return context.runner or {}
end

local function test_dir(context)
	return runner_cfg(context).test_dir or "test"
end

local function use_bundle(context)
	local runner = runner_cfg(context)
	if runner.bundle ~= nil then
		return runner.bundle
	end
	return fs.exists(context.target_path .. "/Gemfile")
end

local function verbose_enabled(context)
	local runner = runner_cfg(context)
	if runner.verbose ~= nil then
		return runner.verbose
	end
	return true
end

local function include_patterns(context)
	local runner = runner_cfg(context)
	return runner.include or DEFAULT_INCLUDE
end

local function exclude_patterns(context)
	local runner = runner_cfg(context)
	return runner.exclude or DEFAULT_EXCLUDE
end

local function is_excluded(path, patterns)
	for _, pattern in ipairs(patterns) do
		if filter.glob_match(path, pattern) then
			return true
		end
	end
	return false
end

local function relative_path(base, path)
	if path:sub(1, #base + 1) == base .. "/" then
		return path:sub(#base + 2)
	end
	if path:sub(1, #base) == base then
		return path:sub(#base + 1):gsub("^/", "")
	end
	return path
end

local function glob_tests(context)
	local tests = {}
	local seen = {}
	local base = context.target_path
	local excludes = exclude_patterns(context)

	for _, pattern in ipairs(include_patterns(context)) do
		for _, path in ipairs(fs.glob(base, pattern)) do
			if not is_excluded(path, excludes) then
				local rel = relative_path(base, path)
				if not seen[rel] then
					seen[rel] = true
					table.insert(tests, rel)
				end
			end
		end
	end

	table.sort(tests)
	return tests
end

local function apply_filters(tests, context)
	if not context.filters then
		return tests
	end

	local filtered = {}
	for _, id in ipairs(tests) do
		if filter.matches({ id = id }, context.filters) then
			table.insert(filtered, id)
		end
	end
	return filtered
end

local function list_rake_tasks(context)
	local tasks = {}
	local cmd
	local args

	if use_bundle(context) then
		cmd = "bundle"
		args = { "exec", "rake", "-T", "test" }
	else
		cmd = "rake"
		args = { "-T", "test" }
	end

	local result = sys.run(cmd, args, { cwd = context.target_path })
	if result.exit_code ~= 0 then
		return tasks
	end

	for line in result.stdout:gmatch("[^\r\n]+") do
		local task = line:match("^rake (test[%w:]*)")
		if task then
			table.insert(tasks, "rake:" .. task)
		end
	end

	table.sort(tasks)
	return tasks
end

local function rake_has_test_task(context)
	if not fs.exists(context.target_path .. "/Rakefile") then
		return false
	end

	local cmd
	local args
	if use_bundle(context) then
		cmd = "bundle"
		args = { "exec", "rake", "-T", "test" }
	else
		cmd = "rake"
		args = { "-T", "test" }
	end

	local result = sys.run(cmd, args, { cwd = context.target_path })
	return result.exit_code == 0 and result.stdout:match("rake test") ~= nil
end

local function use_rake(context, tests)
	local runner = runner_cfg(context)
	if runner.use_rake ~= nil then
		return runner.use_rake
	end

	if not rake_has_test_task(context) then
		return false
	end

	for _, id in ipairs(tests) do
		if id:match("^rake:") then
			return true
		end
	end

	return #tests == 0
end

local function append_args(args, extra)
	if not extra then
		return
	end
	for _, value in ipairs(extra) do
		table.insert(args, value)
	end
end

local function build_env(context, coverage)
	local env = {}
	local runner = runner_cfg(context)

	if verbose_enabled(context) then
		env.TESTOPTS = "-v"
	end

	if coverage then
		env.COVERAGE = "true"
		if runner.coverage and runner.coverage.env then
			for key, value in pairs(runner.coverage.env) do
				env[key] = value
			end
		end
	end

	if runner.env then
		for key, value in pairs(runner.env) do
			env[key] = value
		end
	end

	return env
end

local function selected_rake_task(tests)
	for _, id in ipairs(tests) do
		local task = id:match("^rake:(.+)$")
		if task then
			return task
		end
	end
	return "test"
end

function list(context)
	local tests = {}
	local seen = {}

	for _, id in ipairs(glob_tests(context)) do
		if not seen[id] then
			seen[id] = true
			table.insert(tests, id)
		end
	end

	for _, id in ipairs(list_rake_tasks(context)) do
		if not seen[id] then
			seen[id] = true
			table.insert(tests, id)
		end
	end

	return apply_filters(tests, context)
end

function build_command(context)
	local runner = runner_cfg(context)
	local cwd = context.target_path
	local tests = apply_filters(glob_tests(context), context)
	local extra_args = runner.args or {}
	local env = build_env(context, false)

	if use_rake(context, tests) then
		local task = selected_rake_task(tests)
		if use_bundle(context) then
			local args = { "exec", "rake", task }
			append_args(args, extra_args)
			return { command = "bundle", args = args, cwd = cwd, env = env }
		end

		local args = { task }
		append_args(args, extra_args)
		return { command = "rake", args = args, cwd = cwd, env = env }
	end

	local args = { "-I", test_dir(context) }
	if verbose_enabled(context) then
		table.insert(args, "-v")
	end

	if context.filters then
		local pattern = context.filters.name or context.filters.pattern
		if pattern then
			table.insert(args, "-n")
			table.insert(args, pattern)
		end
	end

	append_args(args, extra_args)

	if #tests == 0 then
		table.insert(args, test_dir(context) .. "/")
	else
		for _, path in ipairs(tests) do
			if not path:match("^rake:") then
				table.insert(args, path)
			end
		end
	end

	if use_bundle(context) then
		local bundle_args = { "exec", "ruby" }
		for _, value in ipairs(args) do
			table.insert(bundle_args, value)
		end
		return { command = "bundle", args = bundle_args, cwd = cwd, env = env }
	end

	return { command = "ruby", args = args, cwd = cwd, env = env }
end

function build_coverage_run(context)
	local runner = runner_cfg(context)
	local coverage = runner.coverage or {}
	local spec = build_command(context)
	spec.env = build_env(context, true)

	return {
		command = spec.command,
		args = spec.args,
		env = spec.env,
		cwd = spec.cwd,
		report = coverage.report or "coverage/lcov.info",
		reporter = coverage.reporter or "lcov",
		output = coverage.output or "coverage/teez.msgpack",
		min_line_rate = coverage.min_line_rate,
	}
end

local function parse_progress_char(char)
	if char == "." then
		return { event = "pass" }
	end
	if char == "F" or char == "E" then
		return { event = "fail" }
	end
	if char == "S" then
		return { event = "skip" }
	end
	return nil
end

local function parse_verbose_result(line)
	local id, seconds, status = line:match("^(%S+#%S+)%s*=%s*([%d%.]+)%s+s%s*=%s*(%S)%s*$")
	if not id then
		return nil
	end

	local duration_ms = math.floor((tonumber(seconds) or 0) * 1000 + 0.5)
	if status == "." then
		return { event = "pass", id = id, duration_ms = duration_ms }
	end
	if status == "F" or status == "E" then
		return { event = "fail", id = id, duration_ms = duration_ms }
	end
	if status == "S" then
		return { event = "skip", id = id, duration_ms = duration_ms }
	end

	return nil
end

function parse_line(line)
	if line == "" then
		if pending_failure and pending_failure.id then
			local event = {
				event = "fail",
				id = pending_failure.id,
				msg = (pending_failure.msg or pending_failure.loc or pending_failure.kind):gsub("\n$", ""),
			}
			pending_failure = nil
			return event
		end
		return nil
	end

	local verbose = parse_verbose_result(line)
	if verbose then
		return verbose
	end

	if line:match("^[%.FES]+$") then
		if #line == 1 then
			return parse_progress_char(line)
		end
		return { event = "output", text = line }
	end

	if line:match("^%s*%d+%)%s+(Failure|Error):%s*$") then
		pending_failure = { kind = line:match("Failure") and "Failure" or "Error" }
		return nil
	end

	if pending_failure and not pending_failure.id then
		local id, loc = line:match("^(%S+#%S+)%s+%[([^%]]+)%]:%s*$")
		if id then
			pending_failure.id = id
			pending_failure.loc = loc
			return nil
		end
	end

	if pending_failure and pending_failure.id then
		if line:match("^Finished in ") or line:match("^%d+ runs,") then
			local event = {
				event = "fail",
				id = pending_failure.id,
				msg = (pending_failure.msg or pending_failure.loc or pending_failure.kind):gsub("\n$", ""),
			}
			pending_failure = nil
			return event
		end

		pending_failure.msg = (pending_failure.msg or "")
			.. line
			.. "\n"
		return nil
	end

	if line:match("^%d+ runs,") then
		return { event = "output", text = line }
	end

	return nil
end
