-- teez FRUIT adapter (Fortran unit tests via CTest or FRUIT driver executables)

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

local function default_coverage_cfg(_context)
    return {
        command = "gcovr",
        report = "coverage/lcov.info",
        output = "coverage/teez.msgpack",
        reporter = "msgpack",
    }
end

local function effective_coverage_cfg(context)
    return shallow_merge(default_coverage_cfg(context), coverage_cfg(context))
end

local function join_path(root, child)
    if child:sub(1, 1) == "/" then
        return child
    end
    return root .. "/" .. child
end

local function normalize_path(value)
    return value:gsub("\\", "/")
end

local function path_exists(path)
    return fs.exists(path) or fs.exists(normalize_path(path))
end

local BUILD_DIR_CANDIDATES = {
    "build",
    "cmake-build-debug",
    "cmake-build-release",
    "cmake-build-relwithdebinfo",
    "_build",
    "Build",
}

local function ctest_testfile(build_dir)
    return join_path(build_dir, "CTestTestfile.cmake")
end

local function resolve_build_dir(context)
    local cfg = runner_cfg(context)
    if cfg.build_dir then
        return cfg.build_dir
    end

    local target = target_path(context)
    for _, name in ipairs(BUILD_DIR_CANDIDATES) do
        local candidate = join_path(target, name)
        if path_exists(ctest_testfile(candidate)) then
            return candidate
        end
    end

    return join_path(target, "build")
end

local function has_ctest_build(context)
    return path_exists(ctest_testfile(resolve_build_dir(context)))
end

local function append_runner_args(args, context)
    local cfg = runner_cfg(context)
    if cfg.args then
        for _, arg in ipairs(cfg.args) do
            table.insert(args, arg)
        end
    end
end

local function append_ctest_regex(args, context)
    local cfg = runner_cfg(context)

    if cfg.regex then
        table.insert(args, "-R")
        table.insert(args, cfg.regex)
    end

    if cfg.exclude_regex then
        table.insert(args, "-E")
        table.insert(args, cfg.exclude_regex)
    end

    if context.filters then
        if context.filters.regex then
            table.insert(args, "-R")
            table.insert(args, context.filters.regex)
        end
        if context.filters.exclude_regex then
            table.insert(args, "-E")
            table.insert(args, context.filters.exclude_regex)
        end
    end
end

local function ctest_base_args(context)
    local args = { "--output-on-failure" }
    local cfg = runner_cfg(context)

    if cfg.config then
        table.insert(args, "-C")
        table.insert(args, cfg.config)
    end

    if cfg.parallel and tonumber(cfg.parallel) and tonumber(cfg.parallel) > 0 then
        table.insert(args, "-j")
        table.insert(args, tostring(cfg.parallel))
    end

    append_ctest_regex(args, context)
    append_runner_args(args, context)
    return args
end

local function parse_ctest_list_line(line)
    local name = line:match("^%s*Test%s+#%d+:%s+(.+)$")
    if name then
        return trim(name)
    end
    return nil
end

local function filter_test_ids(tests, context)
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

local function list_via_ctest(context)
    local build_dir = resolve_build_dir(context)
    local args = { "-N" }
    local cfg = runner_cfg(context)

    if cfg.config then
        table.insert(args, "-C")
        table.insert(args, cfg.config)
    end

    append_ctest_regex(args, context)
    append_runner_args(args, context)

    local output = sys.exec("ctest", args, { cwd = build_dir })
    local tests = {}
    for line in output:gmatch("[^\r\n]+") do
        local id = parse_ctest_list_line(line)
        if id then
            table.insert(tests, id)
        end
    end
    table.sort(tests)
    return filter_test_ids(tests, context)
end

local function executable_name(path)
    local normalized = normalize_path(path)
    return normalized:match("([^/]+)$") or normalized
end

local function discover_fruit_executables(context)
    local cfg = runner_cfg(context)
    if cfg.executables then
        return cfg.executables
    end

    local build_dir = resolve_build_dir(context)
    local patterns = cfg.executable_globs or {
        "*fruit*",
        "*_fruit_test",
        "fruit_driver*",
        "run_fruit*",
    }
    local executables = {}
    local seen = {}

    for _, pattern in ipairs(patterns) do
        for _, file in ipairs(fs.glob(build_dir, pattern)) do
            local resolved = join_path(build_dir, file)
            local name = executable_name(resolved)
            if not seen[name] then
                seen[name] = true
                table.insert(executables, resolved)
            end
        end
    end

    table.sort(executables)
    return executables
end

local function list_via_executables(context)
    local tests = {}
    for _, executable in ipairs(discover_fruit_executables(context)) do
        table.insert(tests, executable_name(executable))
    end
    return filter_test_ids(tests, context)
end

local function build_ctest_command(context)
    local build_dir = resolve_build_dir(context)
    local args = ctest_base_args(context)
    table.insert(args, "--verbose")

    return {
        command = "ctest",
        args = args,
        cwd = build_dir,
    }
end

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function build_executable_command(context)
    local cfg = runner_cfg(context)
    local executables = discover_fruit_executables(context)
    if #executables == 0 then
        error(
            "no FRUIT test executables found in build directory; configure CMake with FRUIT or set runners.fruit.executables"
        )
    end

    local driver_args = cfg.driver_args or {}
    local fragments = {}
    for _, executable in ipairs(executables) do
        local tokens = { shell_quote(executable) }
        for _, arg in ipairs(driver_args) do
            table.insert(tokens, shell_quote(arg))
        end
        table.insert(fragments, table.concat(tokens, " "))
    end

    return {
        command = "sh",
        args = { "-c", table.concat(fragments, " && ") },
        cwd = resolve_build_dir(context),
    }
end

local function build_gcovr_args(context, cov)
    local build_dir = resolve_build_dir(context)
    local args = {
        "--root",
        target_path(context),
        "--exclude-unreachable-branches",
        "--exclude-throw-branches",
        "--print-summary",
        "--lcov",
        cov.report or "coverage/lcov.info",
    }

    if cov.exclude then
        for _, pattern in ipairs(cov.exclude) do
            table.insert(args, "--exclude")
            table.insert(args, pattern)
        end
    end

    if cov.include then
        for _, pattern in ipairs(cov.include) do
            table.insert(args, "--filter")
            table.insert(args, pattern)
        end
    end

    table.insert(args, build_dir)
    return args
end

function prefetch_starts()
    return false
end

function list(context)
    if has_ctest_build(context) then
        return list_via_ctest(context)
    end
    return list_via_executables(context)
end

function build_command(context)
    if has_ctest_build(context) then
        return build_ctest_command(context)
    end
    return build_executable_command(context)
end

function build_coverage_run(context)
    local cov = effective_coverage_cfg(context)
    local build_dir = resolve_build_dir(context)
    local run = build_command(context)
    run.cwd = build_dir

    local collect_command = cov.command or "gcovr"
    run.collect = {
        command = collect_command,
        args = build_gcovr_args(context, cov),
        cwd = build_dir,
    }

    run.report = cov.report or "coverage/lcov.info"
    run.reporter = cov.reporter or "msgpack"
    run.output = cov.output or "coverage/teez.msgpack"
    run.min_line_rate = cov.min_line_rate
    return run
end

local function with_duration(event, duration_ms)
    if duration_ms ~= nil then
        event.duration_ms = duration_ms
    end
    return event
end

local function parse_ctest_result(line)
    local id, status, duration = line:match(
        "^%s*%d+/%d+%s+Test%s+#%d+:%s+(.-)%s+%.+%s+(Passed|Failed|PASSED|FAILED|Not Run|Disabled)%s+([%d%.]+)%s+sec"
    )
    if not id then
        return nil
    end

    id = trim(id)
    duration = tonumber(duration)
    local duration_ms = duration and math.floor(duration * 1000) or nil

    if status == "Passed" or status == "PASSED" then
        return with_duration({ event = "pass", id = id }, duration_ms)
    end

    if status == "Failed" or status == "FAILED" then
        return with_duration({ event = "fail", id = id, msg = "CTest reported failure" }, duration_ms)
    end

    if status == "Not Run" or status == "Disabled" then
        return with_duration({ event = "skip", id = id }, duration_ms)
    end

    return nil
end

local function parse_ctest_start(line)
    local id = line:match("^%s*Start%s+%d+:%s+(.+)$")
    if id then
        return { event = "start", id = trim(id) }
    end
    return nil
end

local function parse_fruit_result(line)
    local patterns = {
        { '^%s*Test%s+"([^"]+)"%s+%.%.%.%s+PASSED%s*$', "pass" },
        { '^%s*Test%s+"([^"]+)"%s+%.%.%.%s+FAILED%s*$', "fail" },
        { '^%s*Test%s+(.-)%s+%.%.%.%s+PASSED%s*$', "pass" },
        { '^%s*Test%s+(.-)%s+%.%.%.%s+FAILED%s*$', "fail" },
        { "^%s*%[PASSED%]%s+(.+)$", "pass" },
        { "^%s*%[FAILED%]%s+(.+)$", "fail" },
        { "^%s*%[PASS%]%s+(.+)$", "pass" },
        { "^%s*%[FAIL%]%s+(.+)$", "fail" },
        { "^%s*PASS:?%s+(.+)$", "pass" },
        { "^%s*FAIL:?%s+(.+)$", "fail" },
        { "^%s*Passed:?%s+(.+)$", "pass" },
        { "^%s*Failed:?%s+(.+)$", "fail" },
        { "^%s*PASSED%s*[-:>]%s*(.+)$", "pass" },
        { "^%s*FAILED%s*[-:>]%s*(.+)$", "fail" },
        { "^%s*Success:?%s+(.+)$", "pass" },
        { "^%s*Failure:?%s+(.+)$", "fail" },
        { "^%s*SKIP:?%s+(.+)$", "skip" },
        { "^%s*%[SKIPPED%]%s+(.+)$", "skip" },
    }

    for _, matcher in ipairs(patterns) do
        local id = line:match(matcher[1])
        if id then
            id = trim(id)
            if matcher[2] == "pass" then
                return { event = "pass", id = id }
            end
            if matcher[2] == "fail" then
                return { event = "fail", id = id, msg = "FRUIT reported failure" }
            end
            return { event = "skip", id = id }
        end
    end

    return nil
end

local function parse_fruit_start(line)
    local id = line:match('^%s*Start:?%s+"([^"]+)"%s*$')
    if id then
        return { event = "start", id = trim(id) }
    end

    id = line:match("^%s*Start:?%s+(.+)$")
    if id then
        return { event = "start", id = trim(id) }
    end

    return nil
end

function parse_line(line)
    line = trim(line)
    if line == "" then
        return nil
    end

    local event = parse_ctest_result(line)
    if event then
        return event
    end

    event = parse_ctest_start(line)
    if event then
        return event
    end

    event = parse_fruit_result(line)
    if event then
        return event
    end

    event = parse_fruit_start(line)
    if event then
        return event
    end

    if line:match("The following tests FAILED:") then
        return { event = "output", text = line }
    end

    if line:match("FAILED%s*:%s*%d+") or line:match("PASSED%s*:%s*%d+") then
        return { event = "output", text = line }
    end

    return nil
end
