-- teez Rust adapter (cargo test)

local DEFAULT_INCLUDE = {
	"**/tests/**/*.rs",
	"**/src/**/*_test.rs",
	"**/src/**/test_*.rs",
}

local function trim(value)
	return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
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
		tool = "llvm-cov",
		report = "coverage/lcov.info",
		output = "coverage/teez.msgpack",
		reporter = "lcov",
		output_dir = "coverage",
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

local function has_cargo_project(target)
	return fs.exists(target .. "/Cargo.toml")
end

local function has_test_sources(context)
	local target = target_path(context)
	for _, pattern in ipairs(include_patterns(context)) do
		if #fs.glob(target, pattern) > 0 then
			return true
		end
	end
	return false
end

local function filter_pattern(context)
	local cfg = runner_cfg(context)
	if cfg.pattern and cfg.pattern ~= "" then
		return cfg.pattern
	end

	if context.filters then
		if type(context.filters.pattern) == "string" and context.filters.pattern ~= "" then
			return context.filters.pattern
		end
		if type(context.filters.names) == "table" and #context.filters.names > 0 then
			return context.filters.names[1]
		end
	end

	return nil
end

local function append_package_args(args, cfg)
	if cfg.package and cfg.package ~= "" then
		table.insert(args, "-p")
		table.insert(args, cfg.package)
	end
end

local function append_test_target_args(args, cfg)
	if cfg.test_target and cfg.test_target ~= "" then
		table.insert(args, "--test")
		table.insert(args, cfg.test_target)
	end
end

local function append_runner_args(args, context)
	local cfg = runner_cfg(context)
	if cfg.args then
		for _, arg in ipairs(cfg.args) do
			table.insert(args, arg)
		end
	end
end

local function append_test_filter(args, context)
	local pattern = filter_pattern(context)
	if pattern then
		table.insert(args, pattern)
	end
end

local function build_cargo_test_args(context, mode)
	local args = { "test" }
	local cfg = runner_cfg(context)

	append_package_args(args, cfg)
	append_test_target_args(args, cfg)
	append_runner_args(args, context)
	append_test_filter(args, context)

	table.insert(args, "--")
	if mode == "list" then
		table.insert(args, "--list")
	elseif mode == "run" then
		table.insert(args, "--nocapture")
	end

	return args
end

local function ensure_built(context)
	local target = target_path(context)
	local cfg = runner_cfg(context)
	local args = { "test", "--no-run" }

	append_package_args(args, cfg)
	append_test_target_args(args, cfg)

	local result = sys.run("cargo", args, { cwd = target })
	if result.exit_code ~= 0 then
		error(trim(result.stderr) ~= "" and result.stderr or result.stdout)
	end
end

local function parse_list_line(line)
	line = trim(line)
	if line == "" then
		return nil
	end

	if line:match(": test%s*$") then
		return line:gsub(": test%s*$", "")
	end

	if line:match(": bench%s*$") then
		return line:gsub(": bench%s*$", "")
	end

	return nil
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

local function collect_tests(context)
	local target = target_path(context)
	if not has_cargo_project(target) then
		return {}
	end

	if not has_test_sources(context) then
		return {}
	end

	ensure_built(context)

	local result = sys.run("cargo", build_cargo_test_args(context, "list"), { cwd = target })
	if result.exit_code ~= 0 then
		error(trim(result.stderr) ~= "" and result.stderr or result.stdout)
	end

	local tests = {}
	local seen = {}
	for line in result.stdout:gmatch("[^\r\n]+") do
		local id = parse_list_line(line)
		if id and not seen[id] then
			seen[id] = true
			table.insert(tests, id)
		end
	end

	table.sort(tests)
	return tests
end

local function coverage_tool(context)
	local cov = effective_coverage_cfg(context)
	local cfg = runner_cfg(context)
	if cfg.coverage_tool and cfg.coverage_tool ~= "" then
		return cfg.coverage_tool
	end
	if cov.tool and cov.tool ~= "" then
		return cov.tool
	end
	return "llvm-cov"
end

function prefetch_starts()
	return false
end

function list(context)
	return apply_filters(collect_tests(context), context)
end

function build_command(context)
	return {
		command = "cargo",
		args = build_cargo_test_args(context, "run"),
		cwd = target_path(context),
	}
end

function build_list_command(context)
	return {
		command = "cargo",
		args = build_cargo_test_args(context, "list"),
		cwd = target_path(context),
	}
end

function build_coverage_run(context)
	local tool = coverage_tool(context)
	if tool ~= "llvm-cov" and tool ~= "tarpaulin" then
		return nil
	end

	local target = target_path(context)
	local cfg = runner_cfg(context)
	local cov = effective_coverage_cfg(context)
	local report = cov.report or "coverage/lcov.info"
	local output = cov.output or "coverage/teez.msgpack"
	local reporter = cov.reporter or "lcov"

	if tool == "llvm-cov" then
		local args = { "llvm-cov", "test" }
		append_package_args(args, cfg)
		append_test_target_args(args, cfg)

		if cov.args then
			for _, arg in ipairs(cov.args) do
				table.insert(args, arg)
			end
		end

		append_test_filter(args, context)
		table.insert(args, "--lcov")
		table.insert(args, "--output-path")
		table.insert(args, report)

		return {
			command = "cargo",
			args = args,
			cwd = target,
			report = report,
			reporter = reporter,
			output = output,
			min_line_rate = cov.min_line_rate,
		}
	end

	local out_dir = cov.output_dir or "coverage"
	report = cov.report or (out_dir .. "/lcov.info")
	local args = { "tarpaulin" }
	append_package_args(args, cfg)
	append_test_target_args(args, cfg)

	if cov.args then
		for _, arg in ipairs(cov.args) do
			table.insert(args, arg)
		end
	end

	append_test_filter(args, context)
	table.insert(args, "--out")
	table.insert(args, "Lcov")
	table.insert(args, "--output-dir")
	table.insert(args, out_dir)

	return {
		command = "cargo",
		args = args,
		cwd = target,
		report = report,
		reporter = reporter,
		output = output,
		min_line_rate = cov.min_line_rate,
	}
end

function parse_line(line)
	line = trim(line)
	if line == "" then
		return nil
	end

	local id = line:match("^test%s+(.-)%s+%.%.%.%s+ok%s*$")
	if id then
		return { event = "pass", id = id }
	end

	id = line:match("^test%s+(.-)%s+%.%.%.%s+FAILED%s*$")
	if id then
		return { event = "fail", id = id, msg = "FAILED" }
	end

	id = line:match("^test%s+(.-)%s+%.%.%.%s+ignored%s*$")
	if id then
		return { event = "skip", id = id }
	end

	if line:match("^test result:") then
		return { event = "output", text = line }
	end

	return nil
end
