local DEFAULT_INCLUDE = { "**/tests/**", "**/*_test.rexx" }
local DEFAULT_EXCLUDE = { "**/tests/run.rexx", "**/run.rexx" }

local function is_rexx_file(path)
    return path:match("%.rexx$") or path:match("%.rex$")
end

local function merge_patterns(context)
    local include = {}
    local exclude = {}

    for _, pattern in ipairs(DEFAULT_INCLUDE) do
        table.insert(include, pattern)
    end
    for _, pattern in ipairs(DEFAULT_EXCLUDE) do
        table.insert(exclude, pattern)
    end

    local runner = context.runner or {}
    if runner.include then
        for _, pattern in ipairs(runner.include) do
            table.insert(include, pattern)
        end
    end
    if runner.exclude then
        for _, pattern in ipairs(runner.exclude) do
            table.insert(exclude, pattern)
        end
    end

    return include, exclude
end

local function matches_any(path, patterns)
    for _, pattern in ipairs(patterns) do
        if filter.glob_match(path, pattern) then
            return true
        end
    end
    return false
end

local function is_excluded(path, exclude)
    return matches_any(path, exclude)
end

local function is_included(path, include)
    if not is_rexx_file(path) then
        return false
    end
    return matches_any(path, include)
end

local function normalize_id(path)
    return path:gsub("^%./", "")
end

local function collect_tests(context)
    local include, exclude = merge_patterns(context)
    local tests = {}
    local seen = {}

    for _, pattern in ipairs(include) do
        local matches = fs.glob(".", pattern)
        for _, path in ipairs(matches) do
            local id = normalize_id(path)
            if is_included(id, include) and not is_excluded(id, exclude) and not seen[id] then
                seen[id] = true
                table.insert(tests, id)
            end
        end
    end

    table.sort(tests)
    return tests
end

local function filter_tests(tests, filters)
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

local function command_available(name)
    local result = sys.run("which", { name })
    return result.exit_code == 0
end

local function resolve_interpreter(runner)
    if runner and runner.interpreter then
        return runner.interpreter
    end
    if command_available("rexx") then
        return "rexx"
    end
    if command_available("regina") then
        return "regina"
    end
    return "rexx"
end

local function resolve_runner_script(context)
    local runner = context.runner or {}
    if runner.runner then
        return runner.runner
    end

    local candidates = { "tests/run.rexx", "tests/run.rex", "run.rexx", "run.rex" }
    for _, candidate in ipairs(candidates) do
        if fs.exists(candidate) then
            return candidate
        end
    end

    return "tests/run.rexx"
end

local function build_interpreter_spec(interpreter, script, extra_args)
    extra_args = extra_args or {}
    if interpreter == "regina" then
        local args = { "-r", script }
        for _, arg in ipairs(extra_args) do
            table.insert(args, arg)
        end
        return interpreter, args
    end

    local args = { script }
    for _, arg in ipairs(extra_args) do
        table.insert(args, arg)
    end
    return interpreter, args
end

local function build_env(context, extra)
    local env = {}
    if extra then
        for key, value in pairs(extra) do
            env[key] = value
        end
    end

    if context.filters then
        env.TEEZ_FILTERS = json.encode(context.filters)
    end

    local tests = filter_tests(collect_tests(context), context.filters)
    if #tests > 0 then
        env.TEEZ_TEST_FILES = table.concat(tests, "\n")
    end

    return env
end

function list(context)
    return filter_tests(collect_tests(context), context.filters)
end

function build_command(context)
    local runner = context.runner or {}
    local interpreter = resolve_interpreter(runner)
    local script = resolve_runner_script(context)
    local extra_args = runner.args or {}
    local command, args = build_interpreter_spec(interpreter, script, extra_args)

    local spec = {
        command = command,
        args = args,
        env = build_env(context, runner.env),
    }

    if runner.cwd then
        spec.cwd = runner.cwd
    end

    return spec
end

function parse_line(line)
    local pass_id, pass_duration = line:match("^PASS%s+(%S+)%s*(%d*)")
    if pass_id then
        local event = { event = "pass", id = pass_id }
        if pass_duration and pass_duration ~= "" then
            event.duration_ms = tonumber(pass_duration)
        end
        return event
    end

    local fail_id, fail_msg = line:match("^FAIL%s+(%S+)%s*(.*)$")
    if fail_id then
        return {
            event = "fail",
            id = fail_id,
            msg = fail_msg ~= "" and fail_msg or line,
        }
    end

    local skip_id = line:match("^SKIP%s+(%S+)")
    if skip_id then
        return { event = "skip", id = skip_id }
    end

    local start_id = line:match("^START%s+(%S+)")
    if start_id then
        return { event = "start", id = start_id }
    end

    if line:match("%S") then
        return { event = "output", text = line }
    end

    return nil
end

function build_coverage_run(context)
    local runner = context.runner or {}
    if not runner.coverage then
        return nil
    end

    local spec = build_command(context)
    spec.env = spec.env or {}
    spec.env.TEEZ_COVERAGE = "1"

    local coverage_script = runner.coverage_runner or runner.coverage_script or resolve_runner_script(context)
    local interpreter = resolve_interpreter(runner)
    local collect_command, collect_args = build_interpreter_spec(
        interpreter,
        coverage_script,
        runner.coverage_args or { "--coverage" }
    )

    spec.collect = {
        command = collect_command,
        args = collect_args,
        env = spec.env,
    }

    if runner.cwd then
        spec.collect.cwd = runner.cwd
    end

    spec.report = runner.coverage_report or "coverage/rexx-coverage.json"
    spec.reporter = runner.coverage_reporter or "json"
    spec.output = runner.coverage_output or "coverage/teez.msgpack"

    if runner.min_line_rate then
        spec.min_line_rate = runner.min_line_rate
    end

    return spec
end
