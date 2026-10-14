local function trim(line)
    return (line:match("^%s*(.-)%s*$"))
end

local function append_args(args, extra)
    if not extra then
        return
    end
    for _, value in ipairs(extra) do
        table.insert(args, value)
    end
end

local function test_id(class_name, method_name)
    return class_name .. "/" .. method_name
end

local function parse_test_case(line)
    local class_name, method_name, outcome, seconds = line:match(
        "^Test Case '%-[(.-) ([^']+)%]' (started|passed|failed) %(([%d%.]+) seconds%)%.?$"
    )
    if class_name and method_name and outcome then
        local id = test_id(class_name, method_name)
        if outcome == "started" then
            return { event = "start", id = id }
        end

        local event = {
            event = outcome == "passed" and "pass" or "fail",
            id = id,
        }

        if seconds then
            event.duration_ms = math.floor((tonumber(seconds) or 0) * 1000)
        end

        if outcome == "failed" then
            event.msg = line
        end

        return event
    end

    class_name, method_name, outcome = line:match("^Test Case '%-[(.-) ([^']+)%]' (started|passed|failed)%.?$")
    if not class_name or not method_name or not outcome then
        return nil
    end

    local id = test_id(class_name, method_name)
    if outcome == "started" then
        return { event = "start", id = id }
    end

    local event = {
        event = outcome == "passed" and "pass" or "fail",
        id = id,
    }
    if outcome == "failed" then
        event.msg = line
    end
    return event
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

local function apply_run_filters(args, context)
    if not context.filters then
        return
    end

    if context.filters.names then
        for _, name in ipairs(context.filters.names) do
            table.insert(args, "--filter")
            table.insert(args, name)
        end
    end

    if context.filters.pattern then
        table.insert(args, "--filter")
        table.insert(args, context.filters.pattern)
    end
end

local function build_test_args(context, extra_flags)
    local args = { "test" }
    append_args(args, extra_flags)

    table.insert(args, "--parallel=false")
    table.insert(args, "-v")

    if context.runner then
        append_args(args, context.runner.args)
    end

    apply_run_filters(args, context)
    return args
end

function list(context)
    local args = { "test", "--list-tests" }
    if context.runner then
        append_args(args, context.runner.list_args)
    end

    local output = sys.exec("swift", args, { cwd = context.target_path })
    local tests = {}

    for line in output:gmatch("[^\r\n]+") do
        line = trim(line)
        if line ~= "" and not line:match("^warning:") and not line:match("^Build complete") then
            table.insert(tests, line)
        end
    end

    return apply_filters(tests, context.filters)
end

function build_command(context)
    return {
        command = "swift",
        args = build_test_args(context),
        cwd = context.target_path,
    }
end

function build_coverage_run(context)
    local spec = build_command(context)
    local args = { "test", "--enable-code-coverage" }

    for i = 2, #spec.args do
        table.insert(args, spec.args[i])
    end
    spec.args = args

    local runner = context.runner or {}
    local profile = runner.profdata or ".build/debug/codecov/default.profdata"
    local object = runner.coverage_object or runner.coverage_binary

    if object then
        spec.collect = {
            command = runner.coverage_command or "llvm-cov",
            args = runner.coverage_args or {
                "export",
                "-format=lcov",
                "-instr-profile=" .. profile,
                object,
            },
        }
        spec.report = runner.coverage_report or "coverage/lcov.info"
        spec.reporter = runner.coverage_reporter or "lcov"
        spec.output = runner.coverage_output or "coverage/lcov.info"
    end

    return spec
end

function parse_line(line)
    local event = parse_test_case(line)
    if event then
        return event
    end

    if line:match("^error:") or line:match("^fatal error:") then
        return { event = "output", text = line }
    end

    return nil
end
