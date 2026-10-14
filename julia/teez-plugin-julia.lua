-- teez Julia adapter (Pkg.test / Test.jl)

local DEFAULT_INCLUDE = { "**/test/**/*.jl", "**/test_*.jl" }

local last_testset = nil

local function trim(value)
	return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function strip_ansi(line)
	return (line:gsub("%\27%[[0-9;]*[A-Za-z]", ""))
end

local function target_path(context)
	return context.target_path or "."
end

local function runner_cfg(context)
	if type(context.runner) == "table" then
		return context.runner
	end
	return {}
end

local function shallow_merge(base, overrides)
	local merged = {}
	for key, value in pairs(base) do
		merged[key] = value
	end
	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			merged[key] = value
		end
	end
	return merged
end

local function coverage_cfg(context)
	local cfg = runner_cfg(context)
	local from_runner = type(cfg.coverage) == "table" and cfg.coverage or {}
	local from_global = type(config) == "table" and type(config.coverage) == "table" and config.coverage
		or {}
	return shallow_merge(from_global, from_runner)
end

local function default_coverage_cfg()
	return {
		report = "coverage/lcov.info",
		output = "coverage/teez.msgpack",
		reporter = "lcov",
		folders = { "src" },
	}
end

local function effective_coverage_cfg(context)
	return shallow_merge(default_coverage_cfg(), coverage_cfg(context))
end

local function resolve_glob_hit(root, file)
	if file:sub(1, 1) == "/" then
		return file
	end
	return root .. "/" .. file
end

local function relative_to(root, path)
	if path:sub(1, #root + 1) == root .. "/" then
		return path:sub(#root + 2)
	end
	return path
end

local function path_excluded(target, pattern)
	return filter.glob_match(target, pattern)
end

local function include_patterns(context)
	local cfg = runner_cfg(context)
	if cfg.include then
		return cfg.include
	end
	return DEFAULT_INCLUDE
end

local function exclude_patterns(context)
	local cfg = runner_cfg(context)
	return cfg.exclude or {}
end

local function is_test_file(path)
	return path:match("%.jl$") ~= nil
end

local function collect_test_files(context)
	local target = target_path(context)
	local paths = {}
	local seen = {}

	for _, pattern in ipairs(include_patterns(context)) do
		if pattern:match("%.jl$") then
			for _, file in ipairs(fs.glob(target, pattern)) do
				local resolved = resolve_glob_hit(target, file)
				if is_test_file(resolved) and not seen[resolved] then
					seen[resolved] = true
					table.insert(paths, relative_to(target, resolved))
				end
			end
		else
			for _, file in ipairs(fs.glob(target, pattern .. "/**/*.jl")) do
				local resolved = resolve_glob_hit(target, file)
				if is_test_file(resolved) and not seen[resolved] then
					seen[resolved] = true
					table.insert(paths, relative_to(target, resolved))
				end
			end
			for _, file in ipairs(fs.glob(target, pattern .. "/*.jl")) do
				local resolved = resolve_glob_hit(target, file)
				if is_test_file(resolved) and not seen[resolved] then
					seen[resolved] = true
					table.insert(paths, relative_to(target, resolved))
				end
			end
		end
	end

	for _, path in ipairs(paths) do
		local resolved = resolve_glob_hit(target, path)
		local excluded = false
		for _, exclude_pattern in ipairs(exclude_patterns(context)) do
			if path_excluded(resolved, exclude_pattern) or path_excluded(path, exclude_pattern) then
				excluded = true
				break
			end
		end
		if excluded then
			seen[path] = nil
		end
	end

	local filtered = {}
	for _, path in ipairs(paths) do
		if seen[path] then
			table.insert(filtered, path)
		end
	end

	table.sort(filtered)
	return filtered
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

local function read_package_name(target)
	local project = target .. "/Project.toml"
	if not fs.exists(project) then
		return nil
	end

	local result = sys.run("julia", {
		"-e",
		'import TOML; print(TOML.parsefile(ARGS[1])["name"])',
		project,
	})
	if result.exit_code ~= 0 then
		return nil
	end
	return trim(result.stdout)
end

local function resolve_package(context)
	local cfg = runner_cfg(context)
	if cfg.package and cfg.package ~= "" then
		return cfg.package
	end
	return read_package_name(target_path(context))
end

local function test_project_flag(target)
	if fs.exists(target .. "/test/Project.toml") then
		return "--project=test"
	end
	return "--project=."
end

local function quote_julia_string(value)
	return "'" .. value:gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
end

local function append_julia_args(args, context)
	local cfg = runner_cfg(context)
	if cfg.julia_args then
		for _, arg in ipairs(cfg.julia_args) do
			table.insert(args, arg)
		end
	end
	if cfg.args then
		for _, arg in ipairs(cfg.args) do
			table.insert(args, arg)
		end
	end
end

local function selected_test_files(context)
	if not context.filters then
		return nil
	end
	return apply_filters(collect_test_files(context), context)
end

local function merged_test_args(context, selected)
	local args = {}
	if selected then
		for _, file in ipairs(selected) do
			table.insert(args, file)
		end
	end
	local cfg = runner_cfg(context)
	if cfg.test_args then
		for _, arg in ipairs(cfg.test_args) do
			table.insert(args, arg)
		end
	end
	if #args == 0 then
		return nil
	end
	return args
end

local function build_pkg_test_expr(context, with_coverage)
	local cfg = runner_cfg(context)
	local pkg = resolve_package(context)
	local parts = { "using Pkg" }

	local options = {}
	if with_coverage then
		local cov = effective_coverage_cfg(context)
		if type(cov.trace) == "string" and cov.trace ~= "" then
			table.insert(options, "coverage=" .. quote_julia_string(cov.trace))
		elseif cov.pkg_test == false then
			-- leave coverage collection to manual trace paths
		else
			table.insert(options, "coverage=true")
		end
		if cov.julia_args then
			local julia_args = {}
			for _, arg in ipairs(cov.julia_args) do
				table.insert(julia_args, '"' .. arg:gsub('"', '\\"') .. '"')
			end
			table.insert(options, "julia_args=[" .. table.concat(julia_args, ", ") .. "]")
		end
	end

	local test_args = merged_test_args(context, selected_test_files(context))
	if test_args then
		local quoted = {}
		for _, arg in ipairs(test_args) do
			table.insert(quoted, quote_julia_string(arg))
		end
		table.insert(options, "test_args=[" .. table.concat(quoted, ", ") .. "]")
	end

	local call
	if pkg and pkg ~= "" then
		if #options > 0 then
			call = 'Pkg.test(' .. quote_julia_string(pkg) .. "; " .. table.concat(options, ", ") .. ")"
		else
			call = "Pkg.test(" .. quote_julia_string(pkg) .. ")"
		end
	else
		if #options > 0 then
			call = "Pkg.test(" .. table.concat(options, ", ") .. ")"
		else
			call = "Pkg.test()"
		end
	end

	return table.concat(parts, "; ") .. "; " .. call
end

local function build_direct_file_command(context)
	local target = target_path(context)
	local selected = selected_test_files(context)
	if not selected or #selected ~= 1 then
		return nil
	end

	local args = { test_project_flag(target) }
	append_julia_args(args, context)
	table.insert(args, selected[1])

	return {
		command = "julia",
		args = args,
		cwd = target,
	}
end

local function build_julia_eval_command(context, expr)
	local target = target_path(context)
	local args = { test_project_flag(target) }
	append_julia_args(args, context)
	table.insert(args, "-e")
	table.insert(args, expr)

	return {
		command = "julia",
		args = args,
		cwd = target,
	}
end

local function build_coverage_collect_expr(cov)
	local folders = cov.folders or { "src" }
	local folder_list = {}
	for _, folder in ipairs(folders) do
		table.insert(folder_list, quote_julia_string(folder))
	end

	local report = cov.report or "coverage/lcov.info"

	return table.concat({
		"using Pkg",
		'Pkg.add("Coverage")',
		"using Coverage",
		"using Coverage.LCOV",
		'mkpath(dirname("' .. report:gsub('"', '\\"') .. '"))',
		"local folders = [" .. table.concat(folder_list, ", ") .. "]",
		"local results = CoverageResult[]",
		"for folder in folders",
		"  if isdir(folder)",
		"    append!(results, process_folder(folder))",
		"  end",
		"end",
		'LCOV.write("' .. report:gsub('"', '\\"') .. '", results)',
	}, "; ")
end

function list(context)
	local tests = collect_test_files(context)
	return apply_filters(tests, context)
end

function build_command(context)
	local direct = build_direct_file_command(context)
	if direct then
		return direct
	end
	return build_julia_eval_command(context, build_pkg_test_expr(context, false))
end

function build_coverage_run(context)
	local cov = effective_coverage_cfg(context)
	local collect_expr = build_coverage_collect_expr(cov)

	return {
		command = "julia",
		args = build_julia_eval_command(context, build_pkg_test_expr(context, true)).args,
		cwd = target_path(context),
		collect = {
			command = "julia",
			args = { "--project=.", "-e", collect_expr },
			cwd = target_path(context),
		},
		report = cov.report,
		reporter = cov.reporter,
		output = cov.output,
		min_line_rate = cov.min_line_rate,
	}
end

function parse_line(line)
	line = trim(strip_ansi(line))
	if line == "" then
		return nil
	end

	local testset, detail = line:match("^([^:]+):%s*(.+)$")
	if testset and detail then
		testset = trim(testset)
		if detail:match("^Test Failed") then
			last_testset = testset
			return { event = "fail", id = testset, msg = line }
		end
		if detail:match("^Error During Test") or detail:match("^Interrupted") then
			last_testset = testset
			return { event = "fail", id = testset, msg = line }
		end
		if detail:match("^Test Broken") then
			last_testset = testset
			return { event = "skip", id = testset, msg = line }
		end
	end

	if line:match("^Test Passed") then
		return { event = "pass", id = last_testset or line }
	end

	if line:match("^Test Failed") then
		return { event = "fail", id = last_testset or line, msg = line }
	end

	if line:match("^Error During Test") or line:match("^Interrupted") then
		return { event = "fail", id = last_testset or line, msg = line }
	end

	if line:match("^Test Broken") then
		return { event = "skip", id = last_testset or line, msg = line }
	end

	if line:match("tests passed$") or line:match("Testing .+ tests passed") then
		return { event = "output", text = line }
	end

	if line:match("Some tests did not pass") or line:match("There was an error during testing") then
		return { event = "output", text = line }
	end

	if line:match("^Test Summary:") then
		return { event = "output", text = line }
	end

	local summary_id = line:match("^%s*([^|]+)|")
	if summary_id and line:match("|") then
		summary_id = trim(summary_id)
		if summary_id ~= "" and summary_id ~= "Test Summary:" then
			last_testset = summary_id
		end
	end

	return nil
end
